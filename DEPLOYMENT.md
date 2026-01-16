# Integration Jam-in-a-Box Deployment Guide

## Overview

This document describes the complete deployment process for Integration Jam-in-a-Box on OpenShift, including the automated setup via `setup.yaml` and manual troubleshooting steps.

## Architecture

The deployment consists of:

1. **Setup Pod** (`jam-setup-pod`): Temporary pod that orchestrates the entire setup process
2. **Build Configurations**: Creates container images from GitHub repositories
   - `jam-navigator`: Nginx-based frontend serving the navigator UI
   - `jam-materials-handler`: Node.js service that processes and serves markdown materials
3. **Deployment Pod** (`jam-in-a-box`): Main application pod with multiple containers
   - Init container: Generates configuration from secrets and routes
   - Nginx container: Serves static content and handles authentication
   - MD-handler container: Serves markdown materials with template processing

## Prerequisites

1. **OpenShift Cluster**: Access to OpenShift 4.18+ cluster with cluster-admin privileges
2. **Cloud Pak for Integration**: CP4I installed in `tools` namespace (for platform navigator integration)
3. **GitHub Repositories**: Fork of the following repos (default: IBMIntegration, can use custom fork):
   - `jam-navigator`: Frontend UI
   - `jam-materials`: Markdown content for labs
   - `jam-materials-handler`: Backend service for serving materials
   - `integration-jam-in-a-box`: Main deployment scripts (this repo)

4. **OpenShift CLI**: `oc` command-line tool installed and authenticated

## Quick Start

### 1. Create Namespace

```bash
oc new-project jam-in-a-box
```

### 2. Create ConfigMap with Parameters

```bash
oc create configmap jam-setup-params -n default \
  --from-literal=parameters="--fork=<your-github-org> --navigator-password=<password> --canary=<branch>"
```

**Parameters:**

- `--fork=<org>`: GitHub organization/user (default: IBMIntegration)
- `--navigator-password=<pwd>`: Password for htpasswd authentication (default: jam)
- `--canary=<branch>`: Branch to use for integration-jam-in-a-box repo (default: redesign)
- `--quick`: Skip builds if images already exist (not yet fully tested)

### 3. Deploy Setup Pod

```bash
oc apply -f setup.yaml -n jam-in-a-box
```

### 4. Monitor Progress

```bash
# Watch setup pod
oc logs -f jam-setup-pod -n jam-in-a-box

# Check builds
oc get builds -n jam-in-a-box -w

# Check final deployment
oc get pods -n jam-in-a-box
```

### 5. Access Application

Get the route URL:

```bash
oc get route integration-jam-in-a-box -n jam-in-a-box -o jsonpath='{.spec.host}'
```

Login with username: `jam` and the password you specified.

## Detailed Process Flow

### Phase 1: Setup Pod Initialization

The `setup.yaml` creates:

1. **ServiceAccount** (`jam-setup-sa`) with cluster-admin role
2. **ConfigMap** (`jam-setup-scripts`) with helper scripts:
   - `config-generator.js`: Generates runtime config from secrets/routes
3. **Pod** (`jam-setup-pod`): Executes the main setup script

### Phase 2: Build Phase

The setup pod's `main.sh` script:

1. **Validates Prerequisites**
   - Checks for required tools (`oc`, `jq`, `git`)
   - Verifies OpenShift login
   - Confirms namespace exists

2. **Configures Fork** (if `--fork` specified)
   - Updates `repo-config.json` with fork URLs
   - Example: `--fork=capnajax` changes all repo URLs from IBMIntegration to capnajax

3. **Builds jam-navigator**
   - Fetches `build.yaml` from GitHub (`main` branch)
   - Substitutes template variables (NAME, NAMESPACE, GIT_BRANCH, etc.)
   - Creates ImageStream and BuildConfig
   - Triggers Docker build from nginx:alpine base image
   - Build time: ~20-40 seconds
   - Output: `jam-navigator:latest` image

4. **Builds jam-materials-handler**
   - Fetches `build.yaml` from GitHub (`main` branch)
   - Creates ImageStream and BuildConfig with S2I strategy
   - **Critical**: Must include materials content in the build
   - Build time: ~45-60 seconds
   - Output: `jam-materials-handler:latest` image

### Phase 3: Deployment Phase

1. **Creates Secrets**
   - `navigator-nginx-auth`: htpasswd file for basic auth
   - `navigator-credentials`: Username/password for runtime access

2. **Creates ConfigMaps**
   - `navigator-nginx-config`: Nginx configuration file
   - `navigator-md-handler-config`: MD-handler configuration
   - `navigator-scripts-init`: Config generator script (already exists from setup.yaml)

3. **Applies Deployment**
   - Fetches `deployment.yaml` from GitHub
   - Substitutes template variables (NAME, NAMESPACE, PORT, etc.)
   - Creates Deployment with:
     - **Init Container**: Runs config-generator.js to create runtime config
     - **Nginx Container**: Serves frontend on port 8088
     - **MD-handler Container**: Serves materials on port 8081/8082
   - Creates Services for both containers
   - Creates Routes (main route + md-handler route)

## Known Issues and Solutions

### Issue 1: Materials Not Found in Image

**Symptom**: MD-handler container crashes with "Error: Cannot access base path: /materials"

**Root Cause**: The `jam-materials-handler` build doesn't include the materials content from `jam-materials` repository.

**Solution Options**:

**Option A: Custom S2I Assemble Script** (Recommended)
Create a custom assemble script that clones materials during build:

```bash
# Create ConfigMap with custom assemble script
cat > /tmp/assemble-script.sh <<'EOF'
#!/bin/bash
set -e
echo "---> Installing application source..."
cp -Rf /tmp/src/. ./

echo "---> Cloning jam-materials repository..."
if [ -n "$MATERIALS_GIT_URL" ]; then
  git clone --depth 1 --branch "${MATERIALS_GIT_BRANCH:-main}" "$MATERIALS_GIT_URL" materials
  echo "---> Materials cloned successfully"
fi

echo "---> Building application from source..."
if [ -f package.json ]; then
  npm install --production
fi

echo "---> Fix permissions..."
fix-permissions ./
EOF

oc create configmap materials-handler-s2i \
  --from-file=assemble=/tmp/assemble-script.sh \
  -n jam-in-a-box

# Update BuildConfig to use custom script
oc apply -f - <<EOF
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: jam-materials-handler
  namespace: jam-in-a-box
spec:
  source:
    type: Git
    git:
      uri: https://github.com/<your-fork>/jam-materials-handler.git
      ref: main
    configMaps:
    - configMap:
        name: materials-handler-s2i
      destinationDir: ".s2i/bin"
  strategy:
    type: Source
    sourceStrategy:
      from:
        kind: ImageStreamTag
        name: nodejs:latest
        namespace: openshift
      env:
      - name: MATERIALS_GIT_URL
        value: "https://github.com/<your-fork>/jam-materials.git"
      - name: MATERIALS_GIT_BRANCH
        value: "main"
  output:
    to:
      kind: ImageStreamTag
      name: jam-materials-handler:latest
EOF

# Rebuild
oc start-build jam-materials-handler -n jam-in-a-box
```

**Option B: Multi-Stage Dockerfile**
Modify jam-materials-handler to use a Dockerfile that clones materials during build (requires changes to upstream repo).

**Option C: Volume Mount**
Mount materials as a ConfigMap or PVC (not ideal for large content).

### Issue 2: Build Status Detection

**Symptom**: Setup script reports "Build failed" when build is still running or reports success too early.

**Solution**: The build-management.sh script now polls the actual build phase status every 5 seconds:

```bash
while [[ $elapsed -lt $maxWait ]]; do
  buildStatus=$(oc get build "$buildName" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
  
  case "$buildStatus" in
    Failed|Error|Cancelled)
      log_error "Build $buildName failed with status: $buildStatus"
      return 1
      ;;
    Complete)
      log_success "Build $buildName completed successfully"
      return 0
      ;;
  esac
  
  sleep 5
  elapsed=$((elapsed + 5))
done
```

### Issue 3: Fork Parameter Not Applied

**Symptom**: Builds use IBMIntegration repos instead of specified fork.

**Solution**: Ensure `--fork` parameter is passed from `main.sh` to `build.sh`:

```bash
# In main.sh, add to startHereParams array:
startHereParams+=("--fork=$fork")
```

### Issue 4: Init Container Fails

**Symptom**: Init container crashes looking for secrets or routes.

**Solution**: Ensure all required secrets are created before deployment:

```bash
# In app-deployment.sh, create secrets before applying deployment:
oc create secret generic navigator-credentials \
  --from-literal=username="$NAVIGATOR_USER" \
  --from-literal=password="$NAVIGATOR_PASSWORD" \
  -n "$NAMESPACE"
```

### Issue 5: Registry Refresh Takes Long Time

**Symptom**: Registry refresh step takes 30+ seconds.

**Potential Solution**: Make registry refresh optional or cached (not yet implemented).

## File Structure

```text
integration-jam-in-a-box/
├── main.sh                          # Main setup orchestration
├── setup.yaml                       # One-line deployment manifest
├── repo-config.json                 # Repository URLs with fork support
├── scripts/
│   └── helpers/
│       ├── build.sh                 # Build orchestration
│       └── build/
│           ├── build-management.sh  # Build execution functions
│           ├── app-deployment.sh    # Deployment functions
│           ├── deployment.yaml      # Deployment template
│           ├── config-generator.js  # Runtime config generator
│           └── logging.sh           # Logging utilities
```

## Configuration Files

### repo-config.json

Controls repository URLs with fork support:

```json
{
  "template_vars": {
    "NAVIGATOR_GIT_URL": "https://github.com/IBMIntegration/jam-navigator.git",
    "MATERIALS_GIT_URL": "https://github.com/IBMIntegration/jam-materials.git",
    "MATERIALS_HANDLER_GIT_URL": "https://github.com/IBMIntegration/jam-materials-handler.git"
  },
  "forks": {
    "capnajax": {
      "template_vars": {
        "NAVIGATOR_GIT_URL": "https://github.com/capnajax/jam-navigator.git",
        "MATERIALS_GIT_URL": "https://github.com/capnajax/jam-materials.git",
        "MATERIALS_HANDLER_GIT_URL": "https://github.com/capnajax/jam-materials-handler.git"
      }
    }
  }
}
```

### deployment.yaml Template Variables

- `{{NAME}}`: Application name (jam-in-a-box)
- `{{NAMESPACE}}`: Target namespace
- `{{PORT}}`: Nginx port (8088)
- `{{LABEL_APP}}`: Label for selectors
- `{{ROUTE_BASENAME}}`: Route name
- `{{CP4I_NAMESPACE}}`: Cloud Pak for Integration namespace (tools)

## Troubleshooting Commands

```bash
# Check all resources
oc get all -n jam-in-a-box

# Check setup pod logs
oc logs jam-setup-pod -n jam-in-a-box

# Check build logs
oc logs build/jam-navigator-<N> -n jam-in-a-box
oc logs build/jam-materials-handler-<N> -n jam-in-a-box

# Check deployment pod logs
POD=$(oc get pods -n jam-in-a-box -l app=jam-in-a-box -o name | head -1)
oc logs $POD -c nginx -n jam-in-a-box
oc logs $POD -c md-handler -n jam-in-a-box
oc logs $POD -c setup -n jam-in-a-box  # init container

# Check deployment status
oc describe deployment jam-in-a-box -n jam-in-a-box

# Check secrets
oc get secrets -n jam-in-a-box | grep navigator

# Check configmaps
oc get configmaps -n jam-in-a-box | grep navigator

# Check routes
oc get routes -n jam-in-a-box

# Restart deployment
oc rollout restart deployment/jam-in-a-box -n jam-in-a-box

# Delete and redeploy
oc delete pod jam-setup-pod -n jam-in-a-box
oc delete deployment jam-in-a-box -n jam-in-a-box
oc apply -f setup.yaml -n jam-in-a-box
```

## Clean Up

```bash
# Delete entire namespace
oc delete project jam-in-a-box

# Or delete individual resources
oc delete deployment jam-in-a-box -n jam-in-a-box
oc delete buildconfig jam-navigator jam-materials-handler -n jam-in-a-box
oc delete imagestream jam-navigator jam-materials-handler -n jam-in-a-box
oc delete service jam-in-a-box -n jam-in-a-box
oc delete route integration-jam-in-a-box -n jam-in-a-box
oc delete pod jam-setup-pod -n jam-in-a-box
```

## Build Time Expectations

- **jam-navigator**: 20-40 seconds (simple nginx:alpine image)
- **jam-materials-handler**: 45-60 seconds (Node.js S2I build)
- **Total setup time**: 2-4 minutes (including builds, deployment, and initialization)

## Security Considerations

1. **ServiceAccount Permissions**: The jam-setup-sa has cluster-admin role to create resources and query CP4I components
2. **Basic Auth**: Nginx uses htpasswd for simple authentication
3. **Secrets**: Credentials stored in OpenShift secrets, mounted as files
4. **Network**: Routes use edge TLS termination with redirect from HTTP

## Future Improvements

1. **Multi-source Build Support**: Properly implement materials inclusion in build (currently blocked by OpenShift API limitations)
2. **Quick Mode**: Optimize builds to reuse existing images when possible
3. **Registry Refresh Optimization**: Cache or make optional
4. **Health Checks**: Add proper liveness/readiness probes
5. **Resource Limits**: Define CPU/memory limits for containers
6. **Persistent Storage**: Consider PVC for materials if they become too large for ConfigMaps
7. **Automated Testing**: Add integration tests for deployment validation

## Support

For issues or questions:

1. Check the logs using troubleshooting commands above
2. Review `issues.md` for known issues
3. Check GitHub Issues in the integration-jam-in-a-box repository
