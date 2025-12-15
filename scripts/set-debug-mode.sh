#!/bin/bash

# patch a deployment, to set NODE_ENV=development in its env vars for the
# `md-handler` container of the `jam-in-a-box` deployment in the
# `jam-in-a-box` namespace
set -e

NODE_ENV_VALUE="${1:-development}"

function getCurrentValue {
  oc -n jam-in-a-box get deployment jam-in-a-box -o json | \
  jq -r '.spec.template.spec.containers[]|select(.name=="md-handler").env[]|select(.name=="NODE_ENV").value'
}

if [ "$(getCurrentValue)" == "$NODE_ENV_VALUE" ]; then
  echo "NODE_ENV is already set to '$NODE_ENV_VALUE'"
else
  echo "Setting NODE_ENV to '$NODE_ENV_VALUE'"
  oc set env deployment/jam-in-a-box -n jam-in-a-box \
    -c md-handler NODE_ENV="${NODE_ENV_VALUE}"
  echo "NODE_ENV is now set to $(getCurrentValue)"
fi
