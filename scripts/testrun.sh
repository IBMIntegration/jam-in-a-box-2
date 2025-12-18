#!/bin/bash

# Script to create an archive of integration-jam-in-a-box and deploy to nginx pod
# Usage: ./scripts/testrun.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NAMESPACE="jam-in-a-box"
POD_NAME="archive-helper"
ARCHIVE_NAME="jam-in-a-box.tar"
ARCHIVE_PATH="/tmp/${ARCHIVE_NAME}"
UPLOAD_DIR="/usr/share/nginx/html"
NAVIGATOR_DIR="$(cd "$REPO_DIR/../jam-navigator" && pwd)"
MATERIALS_DIR="$(cd "$REPO_DIR/../jam-materials" && pwd)"
MATERIALS_HANDLER_DIR="$(cd "$REPO_DIR/../jam-materials-handler" && pwd)"

isCopyMaterials=false
isRebuildMaterialsHandler=false
for arg in "$@"; do
  case $arg in
    --copy-materials)
      isCopyMaterials=true
      shift
      ;;
    --rebuild-materials-handler)
      isRebuildMaterialsHandler=true
      shift
      ;;
    --namespace=*)
      NAMESPACE="${arg#*=}"
      shift
      ;;
    *)
      ;;
  esac
done

function h1 {
  echo 
  echo $'\x1b[1;4;96m'"$*"$'\x1b[0m'
  echo
}

h1 "Building materials archives"

echo "==> Creating archive of integration-jam-in-a-box..."
cd "$REPO_DIR"
tar -cf "$ARCHIVE_PATH" \
  --exclude='node_modules' \
  --exclude='.git' \
  --exclude='*.log' \
  --exclude='.DS_Store' \
  --no-xattrs \
  .

echo "==> Archive created: $ARCHIVE_PATH ($(du -h "$ARCHIVE_PATH" | cut -f1))"

h1 "Preparing ${POD_NAME} pod in namespace ${NAMESPACE}"

echo "==> Checking if namespace $NAMESPACE exists..."
if ! oc get namespace "$NAMESPACE" &>/dev/null; then
  echo "==> Creating namespace $NAMESPACE..."
  oc create namespace "$NAMESPACE"
fi

echo "==> Checking if pod $POD_NAME exists in namespace $NAMESPACE..."
if oc get pod "$POD_NAME" -n "$NAMESPACE" &>/dev/null; then
  echo "==> Pod $POD_NAME already exists"
  POD_STATUS=$(oc get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
  if [[ "$POD_STATUS" != "Running" ]]; then
    echo "==> Warning: Pod is in $POD_STATUS state, waiting for it to be ready..."
    oc wait --for=condition=Ready pod/"$POD_NAME" -n "$NAMESPACE" --timeout=60s
  fi
else
  echo "==> Creating nginx pod with emptyDir volume..."

  pvcYaml="$(cat "${SCRIPT_DIR}/helpers/build/pvc.yaml")"
  pvcYaml="${pvcYaml//\{\{NAMESPACE\}\}/$NAMESPACE}"
  echo "$pvcYaml" | oc apply -n "$NAMESPACE" -f -

  # Create service account with build permissions
  echo "==> Creating service account with build permissions..."
  cat <<EOF | oc apply -n "$NAMESPACE" -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: archive-helper-sa
  namespace: $NAMESPACE
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: archive-helper-role
  namespace: $NAMESPACE
rules:
- apiGroups: ["build.openshift.io"]
  resources: ["buildconfigs", "builds"]
  verbs: ["get", "list", "watch", "create", "patch", "update"]
- apiGroups: ["build.openshift.io"]
  resources: ["buildconfigs/instantiate", "buildconfigs/instantiatebinary"]
  verbs: ["create"]
- apiGroups: [""]
  resources: ["pods", "pods/log"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: archive-helper-binding
  namespace: $NAMESPACE
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: archive-helper-role
subjects:
- kind: ServiceAccount
  name: archive-helper-sa
  namespace: $NAMESPACE
EOF

  cat <<EOF | oc apply -n "$NAMESPACE" -f -
apiVersion: v1
kind: Pod
metadata:
  name: $POD_NAME
  namespace: $NAMESPACE
  labels:
    app: $POD_NAME
spec:
  serviceAccountName: archive-helper-sa
  initContainers:
  - name: fix-permissions
    image: busybox:latest
    command: ['sh', '-c', 'chmod -R a+w /materials || true']
    volumeMounts:
    - name: materials-storage
      mountPath: /materials
  containers:
  - name: nginx
    image: nginx:latest
    ports:
    - containerPort: 80
    volumeMounts:
    - name: htdocs-storage
      mountPath: /usr/share/nginx/html
    - name: materials-storage
      mountPath: /materials
    - name: materials-handler-storage
      mountPath: /materials-handler-data
    - name: local-bin-storage
      mountPath: /usr/local/bin
  volumes:
  - name: htdocs-storage
    persistentVolumeClaim:
      claimName: htdocs-pvc
  - name: materials-storage
    persistentVolumeClaim:
      claimName: materials-pvc
  - name: materials-handler-storage
    persistentVolumeClaim:
      claimName: materials-handler-sources-pvc
  - name: local-bin-storage
    emptyDir:
      sizeLimit: 1Gi
---
apiVersion: v1
kind: Service
metadata:
  name: $POD_NAME
  namespace: $NAMESPACE
  labels:
    app: $POD_NAME
spec:
  selector:
    app: $POD_NAME
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
  type: ClusterIP
EOF

  echo "==> Waiting for pod to be ready..."
  oc wait --for=condition=Ready pod/"$POD_NAME" -n "$NAMESPACE" --timeout=120s
fi

h1 "Installing oc binary in pod"

# if the oc command isn't already there, load it into /usr/local/bin in the pod
if [ "$isRebuildMaterialsHandler" = true ]; then
  if ! oc exec "$POD_NAME" -n "$NAMESPACE" -- which oc &>/dev/null; then
    echo "==> Copying oc binary to pod..."
    ocDlDir="$(mktemp -d)"
    curl https://github.com/openshift/okd/releases/download/4.14.0-0.okd-2023-12-01-225814/openshift-client-linux-4.14.0-0.okd-2023-12-01-225814.tar.gz  \
      -L -o "$ocDlDir/oc.tar.gz"
    (cd "$ocDlDir" && tar -xzf "oc.tar.gz")
    echo "==> oc binary downloaded to $ocDlDir:"
    ls -lh "$ocDlDir"
    echo "==> Copying oc binary to pod (this will take some time)..."
    gzip -c "$ocDlDir/oc" > "$ocDlDir/oc.gz"
    oc cp "$ocDlDir/oc.gz" "$NAMESPACE/$POD_NAME:/usr/local/bin" -c nginx
    oc exec "$POD_NAME" -n "$NAMESPACE" -c nginx -- gunzip /usr/local/bin/oc.gz
    oc exec "$POD_NAME" -n "$NAMESPACE" -c nginx -- chmod +x /usr/local/bin/oc
    if oc exec "$POD_NAME" -n "$NAMESPACE" -c nginx -- which oc
    then
      echo "==> oc binary copied to pod."
    else
      echo "==> Warning: oc binary not found in pod after copy."
    fi
    rm -rf "$ocDlDir"
    echo "==> cleaned up temporary oc download directory."
  else
    echo "==> oc binary already present in pod, skipping copy."
  fi
else
  echo "==> Skipping oc binary copy to pod, only necessary when using --copy-materials-handler."
fi

h1 "Adding htdocs-pvc volume to jam-in-a-box deployment"

echo "==> Getting nginx container index..."

NGINX_INDEX=$(oc get deployment jam-in-a-box -n "$NAMESPACE" -o json | \
  jq '.spec.template.spec.containers | map(.name) | index("nginx")')
if [ "$NGINX_INDEX" = "null" ] || [ -z "$NGINX_INDEX" ]; then
  echo "==> Error: nginx container not found in deployment"
  exit 1
else
  echo "==> Found nginx container at index: $NGINX_INDEX"
  # Check if volumeMount already exists
  EXISTING_MOUNT=$(oc get deployment jam-in-a-box -n "$NAMESPACE" -o json | \
    jq ".spec.template.spec.containers[$NGINX_INDEX].volumeMounts | map(.name) | index(\"htdocs-storage\")")

  if [ "$EXISTING_MOUNT" != "null" ] && [ -n "$EXISTING_MOUNT" ]; then
    echo "==> htdocs-storage volumeMount already exists at index: $EXISTING_MOUNT"
  else
    echo "==> htdocs-storage volumeMount not found, will be added"
    echo "==> Patching deployment to add htdocs-storage volume and mount..."

    oc patch deployment jam-in-a-box -n "$NAMESPACE" --type=json -p='[
      {
        "op": "add",
        "path": "/spec/template/spec/volumes/-",
        "value": {
          "name": "htdocs-storage",
          "persistentVolumeClaim": {
            "claimName": "htdocs-pvc"
          }
        }
      },
      {
        "op": "add",
        "path": "/spec/template/spec/containers/'"$NGINX_INDEX"'/volumeMounts/0",
        "value": {
          "mountPath": "/usr/share/nginx/html",
          "name": "htdocs-storage"
        }
      }
    ]' && echo "==> Deployment patched successfully" || echo "==> Warning: Failed to patch deployment"
  fi
fi

h1 "Deploying htdocs archive to pod"

echo "==> Copying archive to pod..."
tar --no-xattrs --exclude='.git' --exclude='.DS_Store' --exclude='*/._*' --exclude='._*' \
  -C "$NAVIGATOR_DIR/htdocs" -cf - . | oc exec -i "$POD_NAME" \
  -n "$NAMESPACE" -c nginx -- tar -C $UPLOAD_DIR -xf -

oc cp "$ARCHIVE_PATH" "$NAMESPACE/$POD_NAME:$UPLOAD_DIR/$ARCHIVE_NAME" -c nginx

echo "==> Verifying archive in pod..."
REMOTE_SIZE=$(oc exec "$POD_NAME" -n "$NAMESPACE" -c nginx -- ls -lh "$UPLOAD_DIR/$ARCHIVE_NAME" | awk '{print $5}')
echo "==> Archive successfully copied to pod: $ARCHIVE_NAME ($REMOTE_SIZE)"

echo "==> Listing contents of $UPLOAD_DIR in pod:"
oc exec "$POD_NAME" -n "$NAMESPACE" -c nginx -- ls -lh "$UPLOAD_DIR"

h1 "Deploying materials to pod"

if [ "$isCopyMaterials" = true ]; then
  echo "==> Copying materials to pod..."
  if [ -d "$MATERIALS_DIR" ]; then
    echo "==> Materials directory found: $MATERIALS_DIR"
    echo "==> Copying materials via tar stream (oc rsync not available)..."
    oc exec -i "$POD_NAME" -n "$NAMESPACE" -c nginx -- bash -c "mkdir -p /materials && chmod -R a+w /materials"
    tar -C "$MATERIALS_DIR" -cf - . | oc exec -i "$POD_NAME" -n "$NAMESPACE" -c nginx -- tar -C /materials -xf -
    echo "==> Materials copied to pod."
  else
    echo "==> Error: Materials directory not found: $MATERIALS_DIR"
  fi
  echo "==> Materials copied to pod."
else
  echo "==> Skipping materials copy to pod, use --copy-materials to enable."
fi

h1 "Rebuilding materials handler image in pod"

if [ "$isRebuildMaterialsHandler" = true ]; then
  echo "==> Copying materials handler to pod..."
  if [ -d "$MATERIALS_HANDLER_DIR" ]; then
    echo "==> Materials handler directory found: $MATERIALS_HANDLER_DIR"
    echo "==> Copying materials handler via tar stream (oc rsync not available)..."
    oc exec -i "$POD_NAME" -n "$NAMESPACE" -c nginx -- bash -c "mkdir -p /materials-handler-data && chmod -R a+w /materials-handler-data"
    tar -C "$MATERIALS_HANDLER_DIR" -cf - . | oc exec -i "$POD_NAME" -n "$NAMESPACE" -c nginx -- tar -C /materials-handler-data -xf -
    echo "==> Materials handler copied to pod."
    
    # Patch BuildConfig to use PVC source instead of Git
    echo "==> Patching materials-handler BuildConfig to use PVC source..."
    if oc get buildconfig build-materials-handler -n "$NAMESPACE" &>/dev/null; then
      oc patch buildconfig build-materials-handler -n "$NAMESPACE" --type=json -p '[
        {
          "op": "replace",
          "path": "/spec/source/type",
          "value": "Binary"
        },
        {
          "op": "remove",
          "path": "/spec/source/git"
        }
      ]' 2>/dev/null && echo "==> BuildConfig patched to use binary source" || echo "==> Warning: Failed to patch BuildConfig"
      
      # Trigger build from PVC
      echo "==> Triggering build from PVC..."
      oc exec "$POD_NAME" -n "$NAMESPACE" -- bash -c "
        cd /materials-handler-data
        oc start-build build-materials-handler --from-dir=. --wait=true -n $NAMESPACE
      " && echo "==> Build completed successfully" || echo "==> Warning: Build failed or timed out"
    else
      echo "==> Warning: BuildConfig build-materials-handler not found, skipping patch"
    fi
  else
    echo "==> Error: Materials handler directory not found: $MATERIALS_HANDLER_DIR"
  fi
else
  echo "==> Skipping materials handler copy to pod, use --copy-materials-handler to enable."
fi

h1 "Summary"

echo ""
echo "==> Done! Archive deployed to pod $POD_NAME in namespace $NAMESPACE"
echo "==> To access the pod:"
echo "    oc exec -it $POD_NAME -n $NAMESPACE -- /bin/bash"
echo "==> To extract the archive in the pod:"
echo "    oc exec $POD_NAME -n $NAMESPACE -- tar -xf /archive/$ARCHIVE_NAME -C /archive"

h1 "Restarting the jam-in-a-box deployment"

oc delete rs -l app=navigator -n "$NAMESPACE" --wait=false >/dev/null 2>&1 || true


# echo "==> starting jam-in-a-box/jam-setup-pod..."

# # check the default namespace for jam-setup-params
# if oc get configmap jam-setup-params -n default >/dev/null 2>&1; then
#   echo "==> jam-setup-params configmap already exists in default namespace"
#   # check if it has the parameters key
#   cmparameters=$(oc get configmap jam-setup-params -n default -o jsonpath='{.data.parameters}')
#   if [ -z "$cmparameters" ]; then
#     echo "==> adding parameters key to jam-setup-params configmap in default namespace"
#     oc patch cm jam-setup-params -n default --type=json -p='[{"op":"add", "path":"/data/parameters", "value":"--quick"}]'
#   elif [[ "$cmparameters" != *"--quick"* ]]; then
#     echo "==> updating parameters key to include --quick in jam-setup-params configmap in default namespace"
#     oc patch cm jam-setup-params -n default --type=json -p='[{"op":"replace", "path":"/data/parameters", "value":"'"$cmparameters"' --quick"}]'
#   else
#     echo "==> jam-setup-params configmap already has --quick parameter"
#   fi
# else
#   echo "==> creating jam-setup-params configmap in default namespace"
#   oc create configmap jam-setup-params -n default \
#     --from-literal=parameters="--quick"
# fi

# oc --namespace=jam-in-a-box delete pod jam-setup-pod || true
# oc --namespace=jam-in-a-box apply -f "$SCRIPT_DIR/../setup.yaml"

# echo "==> Waiting for jam-setup-pod to exist..."
# limit=30
# for ((i=1; i<=limit; i++)); do
#   if oc get pod/jam-setup-pod -n jam-in-a-box &>/dev/null; then
#     break
#   fi
#   echo "==> jam-setup-pod not found yet, waiting ($i/$limit)..."
#   sleep 2
# done

# echo "==> Waiting for jam-setup-pod to be running or in error state..."
# oc wait --for=condition=Ready pod/jam-setup-pod -n jam-in-a-box --timeout=300s || \
#   oc get pod jam-setup-pod -n jam-in-a-box -o jsonpath='{.status.phase}' | grep -qE '(Running|Error)' || true

# echo "==> Tailing logs of jam-setup-pod..."
#   oc -n jam-in-a-box logs -f --tail=-1 jam-setup-pod
