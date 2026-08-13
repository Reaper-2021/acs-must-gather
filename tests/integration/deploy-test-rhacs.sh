#!/bin/bash

# Deploy minimal RHACS test installation for integration testing

set -euo pipefail

NAMESPACE="${TEST_NAMESPACE:-stackrox}"

echo "==> Creating namespace: ${NAMESPACE}"
kubectl create namespace "${NAMESPACE}" || true

echo "==> Creating mock Central deployment"
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: central
  namespace: ${NAMESPACE}
  labels:
    app: central
spec:
  replicas: 1
  selector:
    matchLabels:
      app: central
  template:
    metadata:
      labels:
        app: central
    spec:
      containers:
      - name: central
        image: busybox:latest
        command: ["sleep", "3600"]
        ports:
        - containerPort: 8443
          name: api
---
apiVersion: v1
kind: Service
metadata:
  name: central
  namespace: ${NAMESPACE}
spec:
  selector:
    app: central
  ports:
  - port: 443
    targetPort: 8443
    name: https
---
apiVersion: v1
kind: Secret
metadata:
  name: central-htpasswd
  namespace: ${NAMESPACE}
type: Opaque
data:
  password: YWRtaW4xMjM=  # admin123
EOF

echo "==> Creating mock Sensor deployment"
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sensor
  namespace: ${NAMESPACE}
  labels:
    app: sensor
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sensor
  template:
    metadata:
      labels:
        app: sensor
    spec:
      containers:
      - name: sensor
        image: busybox:latest
        command: ["sleep", "3600"]
EOF

echo "==> Creating mock Collector DaemonSet"
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: collector
  namespace: ${NAMESPACE}
  labels:
    app: collector
spec:
  selector:
    matchLabels:
      app: collector
  template:
    metadata:
      labels:
        app: collector
    spec:
      containers:
      - name: collector
        image: busybox:latest
        command: ["sleep", "3600"]
EOF

echo "==> Creating Central CR"
kubectl apply -f - <<EOF
apiVersion: platform.stackrox.io/v1alpha1
kind: Central
metadata:
  name: stackrox-central-services
  namespace: ${NAMESPACE}
spec:
  central:
    exposure:
      loadBalancer:
        enabled: false
  egress:
    connectivityPolicy: Online
EOF

echo "==> Creating SecuredCluster CR"
kubectl apply -f - <<EOF
apiVersion: platform.stackrox.io/v1alpha1
kind: SecuredCluster
metadata:
  name: stackrox-secured-cluster-services
  namespace: ${NAMESPACE}
spec:
  clusterName: test-cluster
  centralEndpoint: central.${NAMESPACE}:443
EOF

echo "==> Waiting for pods to be ready"
kubectl wait --for=condition=available --timeout=60s deployment/central -n "${NAMESPACE}" || true
kubectl wait --for=condition=available --timeout=60s deployment/sensor -n "${NAMESPACE}" || true

echo "==> Test RHACS installation deployed successfully"
kubectl get pods -n "${NAMESPACE}"
