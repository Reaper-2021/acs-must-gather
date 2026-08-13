#!/bin/bash

# Run must-gather in test environment

set -euo pipefail

NAMESPACE="${TEST_NAMESPACE:-stackrox}"
OUTPUT_DIR="/tmp/must-gather-output-$$"

echo "==> Running must-gather"

# Create must-gather pod
kubectl run must-gather-test \
  --image=acs-must-gather:latest \
  --image-pull-policy=Never \
  --restart=Never \
  --rm \
  --attach \
  --timeout=300s \
  --overrides='
{
  "spec": {
    "serviceAccountName": "default",
    "containers": [{
      "name": "must-gather",
      "image": "acs-must-gather:latest",
      "imagePullPolicy": "Never",
      "command": ["/usr/bin/gather"],
      "env": [
        {"name": "MUST_GATHER_DIR", "value": "/must-gather"},
        {"name": "GATHER_DIAGNOSTICS", "value": "true"}
      ],
      "volumeMounts": [{
        "name": "output",
        "mountPath": "/must-gather"
      }]
    }],
    "volumes": [{
      "name": "output",
      "emptyDir": {}
    }]
  }
}
'

echo "==> Must-gather completed"

# For now, mark as successful if pod completed
# In real integration test, we'd extract and validate the output
echo "Must-gather execution test passed"
