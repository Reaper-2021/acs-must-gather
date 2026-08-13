# ACS Must-Gather

A must-gather image for collecting diagnostic information from Red Hat Advanced Cluster Security (RHACS / StackRox) deployments on OpenShift clusters.

## Usage

```sh
oc adm must-gather --image=quay.io/rhn_support_shaising/acs-must-gather:latest
```

This collects data related to ACS components only. For general cluster diagnostics, run `oc adm must-gather` without a custom image.

### Time-bounded collection

```sh
# Collect logs from the last 8 hours
oc adm must-gather --image=quay.io/rhn_support_shaising/acs-must-gather:latest -- /usr/bin/gather MUST_GATHER_SINCE=8h

# Collect logs since a specific time
oc adm must-gather --image=quay.io/rhn_support_shaising/acs-must-gather:latest -- /usr/bin/gather MUST_GATHER_SINCE_TIME=2024-01-15T10:00:00Z
```

## What is collected

### Operator
- RHACS operator namespace (pods, logs, deployments, events)
- OLM resources (ClusterServiceVersion, Subscription, InstallPlan)

### Central Services
- Central deployment, Central DB
- Scanner V4 (indexer, matcher, database)
- Legacy Scanner (if present)
- ConfigMaps, Services, Routes, NetworkPolicies, PVCs, HPAs

### Secured Cluster Services
- Sensor deployment
- Collector DaemonSet
- Admission Controller deployment
- NetworkPolicies

### Cluster-Scoped Resources
- ACS CRDs and CR instances (Central, SecuredCluster, SecurityPolicy)
- ValidatingWebhookConfigurations and MutatingWebhookConfigurations
- ClusterRoles and ClusterRoleBindings
- SecurityContextConstraints (OpenShift)
- Node summary

### Central Diagnostics
- `/v1/metadata` — Central version and build info
- `/v1/clusters` — connected cluster list
- `/v1/centralhealth/upgradestatus` — upgrade/rollback status
- `/v1/database/status` — database health
- `/debug/goroutine` — goroutine stack dump
- `/debug/heap` — heap memory profile
- `/metrics` — Prometheus metrics from Central
- `/api/extensions/diagnostics` — comprehensive diagnostic bundle (PostgreSQL stats, telemetry, auth providers, roles, notifiers, system config, audit logs, multi-cluster K8s resources, sensor metrics)
- `/debug/dump` — debug dump with CPU profiling (30-second CPU profile, mutex profile, goroutines, heap, Prometheus snapshots)

## Diagnostic Bundles Explained

This must-gather collects three types of diagnostic bundles from Central:

### 1. Individual Diagnostic Endpoints
Lightweight JSON/text endpoints collected by default:
- Basic health checks (metadata, cluster list, upgrade status, database status)
- Goroutine dump and heap profile
- Prometheus metrics

### 2. Diagnostic Bundle (`/api/extensions/diagnostics`)
Comprehensive production troubleshooting bundle (ZIP file, ~5-10min collection):
- **PostgreSQL diagnostics**: `pg_stat_statements` (top 1000 queries), index health, analyze stats, tuple stats, active sessions
- **Telemetry data**: Central and Sensor telemetry, deployment stats, feature usage
- **Configuration**: Auth providers, groups, roles, notifiers, system config, delegated scanning config
- **Audit logs**: LogImbue audit trail
- **Multi-cluster data**: Kubernetes resources and logs from all connected secured clusters (via Sensor)
- **Sensor metrics**: Prometheus metrics from all connected sensors

**Note**: Requires Central to be running and healthy. Collection may take several minutes.

### 3. Debug Dump (`/debug/dump`)
Performance debugging bundle with profiling data (ZIP file, ~1-2min collection):
- **CPU profiling**: 30-second pprof CPU profile
- **Memory profiling**: Heap profile, goroutine dump, mutex profile (lock contention)
- **Prometheus snapshots**: Metrics before and after CPU profiling
- **PostgreSQL diagnostics**: Same database stats as Diagnostic Bundle

**Note**: Includes 30 seconds of CPU profiling, so collection takes at least 30s. Use for performance issues, high CPU, memory leaks, or deadlocks.

### When Central is Down
If Central is not running or unhealthy, diagnostic bundle and debug dump collection will fail gracefully with error files. The rest of the must-gather (Kubernetes resources, operator data, cluster-scoped resources) will still be collected successfully.

## Environment Variables

| Variable | Description | Default |
|---|---|---|
| `MUST_GATHER_SINCE` | Duration filter for logs (e.g., `8h`, `30m`) | (all logs) |
| `MUST_GATHER_SINCE_TIME` | ISO 8601 timestamp for log start | (all logs) |
| `MUST_GATHER_DIR` | Output base directory | `/must-gather` |
| `GATHER_DIAGNOSTICS` | Enable Central diagnostic endpoint collection | `true` |
| `INSPECT_TIMEOUT` | Timeout per `oc adm inspect` call (seconds) | `120` |
| `DIAG_TIMEOUT` | Timeout per diagnostic endpoint call (seconds) | `30` |

## Building

```sh
make build
make push
```

## Linting

```sh
make lint
```

Requires [shellcheck](https://www.shellcheck.net/).

## Must-Gather vs roxctl

This must-gather complements the native StackRox diagnostic tools. Here's when to use each:

### Use ACS Must-Gather When:
- ✅ Central is down, crashed, or won't start
- ✅ Troubleshooting operator lifecycle issues (installation, upgrade failures)
- ✅ Need cluster-wide RBAC/webhook troubleshooting
- ✅ Investigating OpenShift-specific issues (Routes, SCCs, OLM)
- ✅ You don't have Central credentials
- ✅ Need comprehensive Kubernetes state snapshot

### Use `roxctl central debug download-diagnostics` When:
- ✅ Central is running and accessible
- ✅ Need multi-cluster visibility (resources from all secured clusters)
- ✅ Have Central credentials with Admin View permission
- ✅ Want to customize collection (filter by cluster, database-only mode, compliance operator data)

### Use `roxctl central debug dump` When:
- ✅ Investigating Central performance issues (high CPU, memory leaks)
- ✅ Need CPU profiling data for performance analysis
- ✅ Debugging deadlocks or lock contention

### Ideal Support Bundle:
For comprehensive troubleshooting, use **both** ACS must-gather **and** the native StackRox diagnostic bundles:
- Must-gather provides the Kubernetes/operator perspective
- Diagnostic bundles provide Central internals and multi-cluster data
- Together they give complete visibility into the RHACS deployment
