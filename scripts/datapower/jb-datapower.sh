#!/bin/bash

GW_NAME="apim-demo-gw"
NAMESPACE="jam-in-a-box"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --namespace=*)
      NAMESPACE="${1#*=}"
      shift
      ;;
    *)
      echo "Unknown parameter: $1"
      exit 1
      ;;
  esac
done

if oc get configmap jb-datapower-config -n "${NAMESPACE}" >/dev/null 2>&1; then
  oc delete configmap jb-datapower-config -n "${NAMESPACE}"
fi
oc create configmap jb-datapower-config -n "${NAMESPACE}" \
  "--from-file=dpApp.cfg=$(dirname "$0")/jb-datapower-dpApp.cfg"

# Note: APIConnectCluster is always in tools namespace where CloudPak is installed
oc patch APIConnectCluster apim-demo --namespace="tools" --type='json' \
  -p='[
    {
      "op":"add",
      "path":"/spec/gateway/additionalDomainConfig",
      "value":[{
        "name":"default",
        "dpApp":{
          "config":["jb-datapower-config"]
        }
      }]
    },
    {
      "op":"replace",
      "path":"/spec/gateway/webGUIManagementEnabled",
      "value": true
    },
    {
      "op":"replace",
      "path":"/spec/gateway/podAutoScaling",
      "value": {
        "method": "VPA",
        "vpa": {
          "maxAllowedCPU": "2000m",
          "maxAllowedMemory": "8Gi"
        }
      }
    }
  ]'

# calculate the name of the console
# consoleHost=$(oc get gatewaycluster $GW_NAME -o json | \
#   jq -r '.spec.gatewayEndpoint.hosts[]|.name' | \
#   sed "s/^${GW_NAME}-[^-]*-/${GW_NAME}-console-/")  

oc apply -f - << EOF
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  labels:
    jb-purpose: datapower-console
  name: ${GW_NAME}-console
  namespace: ${NAMESPACE}
spec:
  port:
    targetPort: 9090
  tls:
    termination: passthrough
  to:
    kind: Service
    name: ${GW_NAME}-datapower
    weight: 100
---
kind: Service
apiVersion: v1
metadata:
  annotations:
    productMetric: VIRTUAL_PROCESSOR_CORE
  name: ${GW_NAME}-lab-ports
  namespace: ${NAMESPACE}
spec:
  ipFamilies:
    - IPv4
  ports:
    - name: lab-mpgw-https-fsh
      protocol: TCP
      port: 10443
      targetPort: 10443
  type: ClusterIP
  selector:
    crd.apiconnect.ibm.com/instance: ${GW_NAME}
    crd.apiconnect.ibm.com/kind: datapower
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  labels:
    jb-purpose: lab
  name: lab-mpgw
  namespace: ${NAMESPACE}
spec:
  port:
    targetPort: 10443
  tls:
    termination: passthrough
  to:
    kind: Service
    name: ${GW_NAME}-lab-endpoints
    weight: 100
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  labels:
    jb-purpose: lab
  name: lab-mpgw
  namespace: ${NAMESPACE}
spec:
  port:
    targetPort: 10443
  tls:
    termination: passthrough
  to:
    kind: Service
    name: ${GW_NAME}-lab-endpoints
    weight: 100
EOF
