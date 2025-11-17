#!/bin/bash

LABEL_APP="jb-start-here"
LABEL="app=${LABEL_APP}"
NAMESPACE="default"

startHereAppPassword=''
quickMode=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --namespace=*)
      NAMESPACE="${1#*=}"
      shift
      ;;
    --password=*)
      startHereAppPassword="${1#*=}"
      shift
      ;;
    --quick)
      quickMode=true
      shift
      ;;
    *)
      echo "Unknown parameter: $1"
      exit 1
      ;;
  esac
done

function cleanup() {

  local globalParams=(-n "$NAMESPACE" "--selector=$LABEL")

  # Clean up any materials loader/checker pods first
  oc delete pod \
    -l app=${LABEL_APP},component=materials-loader \
    -n "$NAMESPACE" --ignore-not-found=true
  oc delete pod \
    -l app=${LABEL_APP},component=materials-checker \
    -n "$NAMESPACE" --ignore-not-found=true

  # Define resource types to clean up
  local resourceTypes=(deployment route service secret configmap pod)
  
  # Add PVC to cleanup only if not in quick mode
  if [ "$quickMode" != true ]; then
    resourceTypes+=(pvc)
    echo "Full cleanup mode - including PVCs"
  else
    echo "Quick mode - preserving PVCs for faster restart"
  fi

  for i in "${resourceTypes[@]}"; do
    if oc get "$i" "${globalParams[@]}" &>/dev/null; then
      oc delete "$i" "${globalParams[@]}"
    fi
  done
}

function generate_password {
  local chars="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  local password=""
  for i in {1..20}; do
    password+="${chars:$((RANDOM % ${#chars})):1}"
  done
  echo "$password"
}

function retry_command() {
  local max_attempts="$1"
  local delay="$2"
  local description="$3"
  shift 3
  
  local attempt=1
  local exit_code=1
  
  while [ $attempt -le $max_attempts ]; do
    echo "Attempt $attempt of $max_attempts: $description"
    
    if "$@"; then
      echo "$description succeeded on attempt $attempt"
      return 0
    fi
    
    exit_code=$?
    echo "$description failed on attempt $attempt (exit code: $exit_code)"
    
    if [ $attempt -lt $max_attempts ]; then
      echo "Waiting ${delay}s before retry..."
      sleep "$delay"
    fi
    
    attempt=$((attempt + 1))
  done
  
  echo "ERROR: $description failed after $max_attempts attempts"
  return $exit_code
}

function create_materials_pvc() {
  local NAME="$1"
  local NAMESPACE="$2"
  
  echo "Creating CephFS PVC for materials archive..."
  
  # Create PVC with retry logic
  retry_command 3 5 "Creating materials PVC" oc apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${NAME}-materials-pvc
  namespace: $NAMESPACE
  labels:
    app: $LABEL_APP
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 5Gi
  storageClassName: ocs-external-storagecluster-cephfs
EOF

  # Wait for PVC to be bound with retry logic
  if ! retry_command 3 10 "Waiting for PVC to bind" \
    wait_for_pvc_bound "$NAME" "$NAMESPACE"; then
    echo "ERROR: PVC failed to bind after multiple attempts. " \
         "Showing diagnostics:"
    oc get pvc ${NAME}-materials-pvc -n "$NAMESPACE" -o wide || \
      echo "PVC not found"
    echo "Available storage classes:"
    oc get sc
    return 1
  fi
  
  echo "PVC successfully created and bound"
  return 0
}

function wait_for_pvc_bound() {
  local NAME="$1"
  local NAMESPACE="$2"
  
  echo "Checking PVC status..."
  local current_status
  current_status=$(oc get pvc ${NAME}-materials-pvc -n "$NAMESPACE" \
    -o jsonpath='{.status.phase}' 2>/dev/null || echo 'Not found')
  echo "PVC status: $current_status"
  
  # Check if PVC already exists and is bound
  if [ "$current_status" = "Bound" ]; then
    echo "PVC is already bound"
    return 0
  fi
  
  # Wait for PVC to become bound
  echo "Waiting up to 2 minutes for PVC to be bound..."
  if oc wait --for=condition=Bound pvc/${NAME}-materials-pvc \
    -n "$NAMESPACE" --timeout=120s; then
    echo "PVC successfully bound"
    return 0
  else
    echo "PVC failed to bind within timeout"
    return 1
  fi
}

function setupNGinX() {

  local NAME="${LABEL_APP}"
  local USERNAME PASSWORD USERNAME_BASE64 PASSWORD_BASE64 yamlFile
  yamlFile="$(dirname "$0")/start-here-app/deployment.yaml"

  echo "Starting setup of Start Here App... ${startHereAppPassword}"

  USERNAME="jam"
  PASSWORD=$(
    if [ -n "${startHereAppPassword}" ]; then
      echo "${startHereAppPassword}";
    else
      generate_password;
    fi
  )
  USERNAME_BASE64=$(echo -n "$USERNAME" | base64)
  PASSWORD_BASE64=$(echo -n "$PASSWORD" | base64)

  PORT=8088

  oc create secret generic ${NAME}-nginx-auth \
    --namespace="$NAMESPACE" \
    --from-literal=.htpasswd="${USERNAME}:$(openssl passwd \
      -apr1 "$PASSWORD")" \
    --dry-run=client -o yaml | \
    oc label --local -f - app="$LABEL_APP" -o yaml | \
    oc apply -f -

  # Create configmap for rest-proxy.js
  oc create configmap ${NAME}-rest-proxy \
    --namespace="$NAMESPACE" \
    --from-file="$(dirname "$0")/start-here-app/rest-proxy.js" \
    --from-file="$(dirname "$0")/start-here-app/config/config.json" \
    --dry-run=client -o yaml | \
    oc label --local -f - app="$LABEL_APP" -o yaml | \
    oc apply -f -

  # Create materials archive PVC using CephFS
  materialsDir="$(dirname "$0")/../../materials"
  if [[ -d "$materialsDir" ]]; then
    # Create PVC with retry logic
    if ! create_materials_pvc "$NAME" "$NAMESPACE"; then
      echo "Failed to create materials PVC after multiple attempts"
      return 1
    fi

    # Check if materials need to be loaded
    shouldLoadMaterials=false
    
    if [ "$quickMode" != true ]; then
      echo "Non-quick mode: will refresh materials data"
      shouldLoadMaterials=true
    else
      # In quick mode, check if materials directory exists in PVC
      echo "Quick mode: checking if materials already exist in PVC..."
      
      # Create a temporary checker pod with retry logic
      if retry_command 3 5 "Creating materials checker pod" oc apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${NAME}-materials-checker
  namespace: $NAMESPACE
  labels:
    app: $LABEL_APP
    component: materials-checker
spec:
  restartPolicy: Never
  containers:
  - name: checker
    image: registry.redhat.io/ubi8/ubi:latest
    command: 
    - 'sh'
    - '-c'
    - 'if [ -d /mnt/materials ] && [ "$(ls -A /mnt/materials)" ]; then echo "MATERIALS_EXIST"; else echo "MATERIALS_MISSING"; fi; sleep 30'
    volumeMounts:
    - name: materials-storage
      mountPath: /mnt/materials
  volumes:
  - name: materials-storage
    persistentVolumeClaim:
      claimName: ${NAME}-materials-pvc
EOF
      then
        # Wait for pod and check result with retry
        if retry_command 3 10 "Waiting for materials checker pod" \
          oc wait --for=condition=Ready pod/${NAME}-materials-checker \
          -n "$NAMESPACE" --timeout=60s; then
          if oc logs ${NAME}-materials-checker -n "$NAMESPACE" | \
            grep -q "MATERIALS_MISSING"; then
            echo "Materials missing in PVC, will load them"
            shouldLoadMaterials=true
          else
            echo "Materials found in PVC, skipping load"
            shouldLoadMaterials=false
          fi
        else
          echo "Warning: Could not check materials status, " \
               "will load them to be safe"
          shouldLoadMaterials=true
        fi
        
        # Clean up checker pod
        oc delete pod ${NAME}-materials-checker \
          -n "$NAMESPACE" --ignore-not-found=true
      else
        echo "Warning: Could not create materials checker pod, " \
             "will load materials to be safe"
        shouldLoadMaterials=true
      fi
    fi
    
    if [ "$shouldLoadMaterials" = true ]; then
      # Clean up any leftover materials-loader pods
      oc delete pod \
        -l app=${LABEL_APP},component=materials-loader \
        -n "$NAMESPACE" --ignore-not-found=true
      
      # Create a temporary pod to copy materials data to the PVC with retry
      echo "Copying materials data to CephFS volume..."
      
      if retry_command 3 5 "Creating materials loader pod" \
        oc apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${NAME}-materials-loader
  namespace: $NAMESPACE
  labels:
    app: $LABEL_APP
    component: materials-loader
spec:
  restartPolicy: Never
  containers:
  - name: loader
    image: registry.redhat.io/ubi8/ubi:latest
    command: ['sleep', '600']
    volumeMounts:
    - name: materials-storage
      mountPath: /mnt/materials
  volumes:
  - name: materials-storage
    persistentVolumeClaim:
      claimName: ${NAME}-materials-pvc
EOF
      then
        # Wait for pod to be ready with retry
        if retry_command 3 10 "Waiting for materials loader pod" \
          oc wait --for=condition=Ready pod/${NAME}-materials-loader \
          -n "$NAMESPACE" --timeout=120s; then
          # Copy materials directory to the mounted volume 
          # (exclude macOS extended attributes)
          # Set COPYFILE_DISABLE to prevent macOS extended attributes in tar
          echo "Copying materials to PVC..."
          
          # Use a function to avoid quote issues
          copy_materials_to_pod() {
            (cd "$(dirname "$materialsDir")" && \
             COPYFILE_DISABLE=1 tar --exclude='._*' --exclude='.DS_Store' \
             --exclude='.Spotlight*' --exclude='.Trashes' -cf - materials) | \
            oc exec -i "${NAME}-materials-loader" -n "$NAMESPACE" -- \
            tar xf - -C /mnt/
          }
          
          if retry_command 2 5 "Copying materials data" copy_materials_to_pod; then
            echo "Materials data successfully copied to CephFS volume"
          else
            echo "ERROR: Failed to copy materials data after retries"
            # Clean up the loader pod
            oc delete pod ${NAME}-materials-loader \
              -n "$NAMESPACE" --ignore-not-found=true
            return 1
          fi
        else
          echo "ERROR: Materials loader pod failed to become ready"
          # Clean up the loader pod
          oc delete pod ${NAME}-materials-loader \
            -n "$NAMESPACE" --ignore-not-found=true
          return 1
        fi
        
        # Clean up the loader pod
        oc delete pod ${NAME}-materials-loader \
          -n "$NAMESPACE" --ignore-not-found=true
      else
        echo "ERROR: Failed to create materials loader pod after retries"
        return 1
      fi
    else
      echo "Skipping materials loading"
    fi
  else
    echo "Warning: materials directory not found at $materialsDir"
  fi

  # Create htdocs archive configmap
  htdocsDir="$(dirname "$0")/start-here-app/htdocs"
  if [[ -d "$htdocsDir" ]]; then
    echo "Creating htdocs archive..."
    (cd "$(dirname "$htdocsDir")" && COPYFILE_DISABLE=1 tar czf - htdocs) | \
    oc create configmap ${NAME}-htdocs \
      --namespace="$NAMESPACE" \
      --from-file=htdocs.tar.gz=/dev/stdin \
      --dry-run=client -o yaml | \
      oc label --local -f - app="$LABEL_APP" -o yaml | \
      oc apply -f -
  else
    echo "Warning: htdocs directory not found at $htdocsDir"
  fi

  # Create extraction script configmap from file
  oc create configmap ${NAME}-scripts \
    --namespace="$NAMESPACE" \
    --from-file="$(dirname "$0")/start-here-app/extract-htdocs.sh" \
    --dry-run=client -o yaml | \
    oc label --local -f - app="$LABEL_APP" -o yaml | \
    oc apply -f -

  # Create config generator script configmap from file
  oc create configmap ${NAME}-scripts-init \
    --namespace="$NAMESPACE" \
    --from-file="$(dirname "$0")/start-here-app/config/config-generator.js" \
    --dry-run=client -o yaml | \
    oc label --local -f - app="$LABEL_APP" -o yaml | \
    oc apply -f -

  # Create md-handler application configmap
  mdHandlerDir="$(dirname "$0")/md-handler"
  if [[ -d "$mdHandlerDir" ]]; then
    echo "Creating md-handler application archive..."
    (cd "$mdHandlerDir" && COPYFILE_DISABLE=1 tar czf - \
      --exclude=node_modules --exclude=test-content --exclude=.git \
      src package.json config.json.example) | \
    oc create configmap ${NAME}-md-handler-app \
      --namespace="$NAMESPACE" \
      --from-file=md-handler.tar.gz=/dev/stdin \
      --dry-run=client -o yaml | \
      oc label --local -f - app="$LABEL_APP" -o yaml | \
      oc apply -f -
  else
    echo "Warning: md-handler directory not found at $mdHandlerDir"
  fi

  # Create md-handler startup script configmap
  cat > /tmp/md-handler-start.sh << 'EOF'
#!/bin/sh
set -e

echo "Setting up md-handler application..."

# Extract application files
cd /app
tar -xzf /app-config/md-handler.tar.gz

# Install dependencies
npm install --only=production

# Copy config files from ConfigMap, but use example if config doesn't exist
if [ -f /app/config/config.json ]; then
  echo "Using config from ConfigMap"
  cp /app/config/config.json /app/config.json
elif [ -f config.json.example ]; then
  echo "Using config.json.example as fallback"
  cp config.json.example config.json
fi

if [ -f /app/config/template-config.json ]; then
  echo "Using template config from ConfigMap"
  cp /app/config/template-config.json /app/template-config.json
fi

echo "Starting md-handler application " \
     "(includes both main and admin servers)..."
# Start the main application which includes both main and admin servers
exec node src/index.js --port 8081 --base-path /materials --host 0.0.0.0
EOF

  oc create configmap ${NAME}-md-handler-scripts \
    --namespace="$NAMESPACE" \
    --from-file=start-md-handler.sh=/tmp/md-handler-start.sh \
    --dry-run=client -o yaml | \
    oc label --local -f - app="$LABEL_APP" -o yaml | \
    oc apply -f -

  rm /tmp/md-handler-start.sh

  # Apply template with substitutions
  output=$(sed -e "s/{{NAME}}/$NAME/g" \
      -e "s/{{NAMESPACE}}/$NAMESPACE/g" \
      -e "s/{{USERNAME}}/$USERNAME/g" \
      -e "s/{{USERNAME_BASE64}}/$USERNAME_BASE64/g" \
      -e "s/{{PASSWORD}}/$PASSWORD/g" \
      -e "s/{{PASSWORD_BASE64}}/$PASSWORD_BASE64/g" \
      -e "s/{{LABEL_APP}}/$LABEL_APP/g" \
      -e "s/{{APP}}/$NAME/g" \
      -e "s/{{PORT}}/$PORT/g" \
      "$yamlFile")

  # Check for any remaining {{}} variables
  remaining=$(echo "$output" | grep -o '{{[^}]*}}' || true)
  if [[ -n "$remaining" ]]; then
    echo "Error: Unsubstituted variables found in main deployment:"
    echo "$remaining" | sort -u
    echo "Template processing failed!"
    return 1
  fi

  # Apply the main deployment
  echo "$output" | oc apply -f -

  # Display access information
  echo ""
  echo "=== Deployment Complete ==="
  echo "Start Here App URL: https://$(oc get route ${NAME} \
    -n "$NAMESPACE" -o jsonpath='{.spec.host}')"
  echo "MD Handler URL: https://$(oc get route ${NAME}-md-handler \
    -n "$NAMESPACE" -o jsonpath='{.spec.host}')"
  echo "Username: $USERNAME"
  echo "Password: $PASSWORD"
  echo "=========================="
}

cleanup
setupNGinX
