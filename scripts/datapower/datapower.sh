#!/bin/bash

GW_NAME="apim-demo-gw"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    *)
      echo "Unknown parameter: $1"
      exit 1
      ;;
  esac
done

if oc get configmap datapower-config -n tools >/dev/null 2>&1; then
  oc delete configmap datapower-config -n tools
fi
oc create configmap datapower-config -n tools \
  "--from-file=dpApp.cfg=$(dirname "$0")/datapower-dpApp.cfg"

# Note: APIConnectCluster is always in tools namespace where CloudPak is installed
oc patch APIConnectCluster apim-demo --namespace="tools" --type='json' \
  -p='[
    {
      "op":"add",
      "path":"/spec/gateway/additionalDomainConfig",
      "value":[{
        "name":"default",
        "dpApp":{
          "config":["datapower-config"]
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
  namespace: tools
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
  namespace: tools
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
  annotations:
    com.ibm.jam-in-a-box: lab
    com.ibm.jam-in-a-box.endpoint.name: "DataPower MPGW Lab Endpoint"
    com.ibm.jam-in-a-box.endpoint.description: |
      This endpoint gives access to the DataPower server on port 10443 for
      lab exercises.
  labels:
    jb-purpose: lab
  name: lab-mpgw
  namespace: tools
spec:
  port:
    targetPort: 10443
  tls:
    termination: passthrough
  to:
    kind: Service
    name: ${GW_NAME}-lab-ports
    weight: 100
EOF
