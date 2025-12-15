#!/bin/bash

# This script updates the nginx password with the current credentials
# stored in the navigator-app-credentials secret.

NS='-n jam-in-a-box'

# shellcheck disable=SC2086
creds64=$(oc get secret navigator-app-credentials $NS -o jsonpath='{.data}')
username=$(echo "$creds64" | jq -r '.username|@base64d')
password=$(echo "$creds64" | jq -r '.password|@base64d')

htpasswd=$(htpasswd -nbB "$username" "$password" | tr -d '\n')

# shellcheck disable=SC2086
oc patch secret navigator-nginx-auth $NS \
  --type='json' -p='[
    { "op": "replace",
      "path": "/data/.htpasswd",
      "value": "'"$(echo -n "$htpasswd" | base64)"'"
    }]'

# shellcheck disable=SC2086
oc exec $NS jam-in-a-box-f7b994bd5-qg4vw -c nginx -- nginx -s reload
