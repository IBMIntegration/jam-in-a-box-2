#!/bin/bash
set -e

# Script to deploy the Gatsby app Node.js pod to Kubernetes
# This script creates a ConfigMap from the start-server.sh file and deploys the Kubernetes resources

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"/gatsby-site
NAMESPACE="${tools:-default}"
NAME='jb-labs'
yamlFile="$(dirname "$0")/gatsby-site/k8s-deployment.yaml"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace=*)
            NAMESPACE="${1#*=}"
            shift
            ;;
        *)
            echo "Unknown option $1"
            exit 1
            ;;
    esac
done

echo "Cleaning up previous deployment if it exists..."
kubectl delete deployment "${NAME}" --namespace="${NAMESPACE}" --ignore-not-found
kubectl delete service "${NAME}" --namespace="${NAMESPACE}" --ignore-not-found
kubectl delete configmap "${NAME}-script" --namespace="${NAMESPACE}" --ignore-not-found

echo "Deploying Gatsby app Node.js pod in namespace ${NAMESPACE}..."

# Create ConfigMap from the start-server.sh script
echo "Creating ConfigMap from start-server.sh..."
kubectl create configmap "${NAME}-script" \
    --from-file=start-server.sh="${SCRIPT_DIR}/start-server.sh" \
    --namespace="${NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -

# Apply the Kubernetes resources
echo "Applying Kubernetes resources..."

# Apply template with substitutions
output=$(sed -e "s/{{NAME}}/$NAME/g" \
    -e "s/{{NAMESPACE}}/$NAMESPACE/g" \
    "$yamlFile")

# Check for any remaining {{}} variables
remaining=$(echo "$output" | grep -o '{{[^}]*}}' || true)
if [[ -n "$remaining" ]]; then
    echo "Error: Unsubstituted variables found:"
    echo "$remaining" | sort -u
    echo "Template processing failed!"
    return 1
fi

# Apply the processed template
echo "$output" | oc apply -f -

echo "Deployment complete!"
echo ""
echo "To check the status:"
echo "  kubectl get pods -l app=nodejs-gatsby -n ${NAMESPACE}"
echo ""
echo "To port-forward and test locally:"
echo "  kubectl port-forward service/nodejs-service 8080:80 -n ${NAMESPACE}"
echo "  Then visit http://localhost:8080"
echo ""
echo "To view logs:"
echo "  kubectl logs -l app=nodejs-gatsby -n ${NAMESPACE}"