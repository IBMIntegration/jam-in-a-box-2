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
MATERIALS_DIR="$(cd "$REPO_DIR/../jam-materials" && pwd)"

isCopyMaterials=false
for arg in "$@"; do
  case $arg in
    --copy-materials)
      isCopyMaterials=true
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

  cat <<EOF | oc apply -n "$NAMESPACE" -f -
apiVersion: v1
kind: Pod
metadata:
  name: $POD_NAME
  namespace: $NAMESPACE
  labels:
    app: $POD_NAME
spec:
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
    - name: archive-storage
      mountPath: /usr/share/nginx/html
    - name: materials-storage
      mountPath: /materials
  volumes:
  - name: archive-storage
    emptyDir:
      sizeLimit: 1Gi
  - name: materials-storage
    persistentVolumeClaim:
      claimName: materials-pvc
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

echo "==> Copying archive to pod..."
oc cp "$ARCHIVE_PATH" "$NAMESPACE/$POD_NAME:$UPLOAD_DIR/$ARCHIVE_NAME"

echo "==> Verifying archive in pod..."
REMOTE_SIZE=$(oc exec "$POD_NAME" -n "$NAMESPACE" -- ls -lh "$UPLOAD_DIR/$ARCHIVE_NAME" | awk '{print $5}')
echo "==> Archive successfully copied to pod: $ARCHIVE_NAME ($REMOTE_SIZE)"

echo "==> Listing contents of $UPLOAD_DIR in pod:"
oc exec "$POD_NAME" -n "$NAMESPACE" -- ls -lh "$UPLOAD_DIR"

if [ "$isCopyMaterials" = true ]; then
  echo "==> Copying materials to pod..."
  if [ -d "$MATERIALS_DIR" ]; then
    echo "==> Materials directory found: $MATERIALS_DIR"
    oc rsync "$MATERIALS_DIR/" "$POD_NAME:/materials" -n "$NAMESPACE"
  else
    echo "==> Error: Materials directory not found: $MATERIALS_DIR"
  fi
  echo "==> Materials copied to pod."
fi

echo ""
echo "==> Done! Archive deployed to pod $POD_NAME in namespace $NAMESPACE"
echo "==> To access the pod:"
echo "    oc exec -it $POD_NAME -n $NAMESPACE -- /bin/bash"
echo "==> To extract the archive in the pod:"
echo "    oc exec $POD_NAME -n $NAMESPACE -- tar -xf /archive/$ARCHIVE_NAME -C /archive"

echo "==> starting jam-in-a-box/jam-setup-pod..."

oc --namespace=jam-in-a-box delete pod jam-setup-pod || true
oc --namespace=jam-in-a-box apply -f "$SCRIPT_DIR/../setup.yaml"

echo "==> Waiting for jam-setup-pod to exist..."
limit=30
for ((i=1; i<=limit; i++)); do
  if oc get pod/jam-setup-pod -n jam-in-a-box &>/dev/null; then
    break
  fi
  echo "==> jam-setup-pod not found yet, waiting ($i/$limit)..."
  sleep 2
done

echo "==> Waiting for jam-setup-pod to be running or in error state..."
oc wait --for=condition=Ready pod/jam-setup-pod -n jam-in-a-box --timeout=300s || \
  oc get pod jam-setup-pod -n jam-in-a-box -o jsonpath='{.status.phase}' | grep -qE '(Running|Error)' || true

echo "==> Tailing logs of jam-setup-pod..."
  oc -n jam-in-a-box logs -f --tail=-1 jam-setup-pod
