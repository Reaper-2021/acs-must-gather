# ACS Must-Gather

A must-gather image for collecting diagnostic information from Red Hat Advanced Cluster Security (RHACS / StackRox) deployments on OpenShift clusters.

## Usage

```sh
oc adm must-gather --image=quay.io/rhn_support_shaising/acs-must-gather:latest
```

This collects data related to ACS components only. For general cluster diagnostics, run `oc adm must-gather` without a custom image.

The image collects three complementary layers of data:

- **acs-must-gather** collects platform-specific data about the OpenShift cluster where RHACS is running (operator, workloads, cluster-scoped resources, RBAC, logs).
- **acs-diagnostic-bundle** collects deep RHACS-related data — the full diagnostic bundle produced by `roxctl central debug download-diagnostics` — from Central and every connected Secured Cluster.
- **acs-debug-dump** collects Central's debug dump — the deepest, Central-focused profiling data produced by `roxctl central debug dump`, including a 30-second CPU profile.

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

### RHACS Diagnostic Bundle

Extracted into the `acs-diagnostic-bundle/` folder. This is the full diagnostic
bundle produced by `roxctl central debug download-diagnostics`, downloaded from
Central's `/api/extensions/diagnostics` endpoint and unpacked so it is browsable
within the must-gather. It contains deep RHACS data from Central and every
connected Secured Cluster, including:

- Build versions and Central-DB (PostgreSQL) diagnostics (`pg_stat` statistics)
- Prometheus metrics and heap / goroutine / mutex profiles
- System configuration, scrubbed auth providers, roles, and notifiers
- Telemetry data
- Kubernetes introspection (resource manifests, pod logs, events) from Central and each Secured Cluster

Central serves this endpoint with admin authentication only. The password is read
from the `central-htpasswd` secret (falling back to `stackrox-admin-password`), and
Central is reached over an `oc port-forward` since Central container images do not
ship `curl`.

### Central Debug Dump

Extracted into the `acs-debug-dump/` folder. This is Central's debug dump,
produced by `roxctl central debug dump` and downloaded from Central's
`/debug/dump` endpoint, then unpacked so it is browsable within the must-gather.
It is the deepest, Central-focused diagnostic layer and includes:

- A 30-second CPU profile, plus heap, goroutine, and mutex profiles
- Two Prometheus metrics passes and Central-DB (PostgreSQL) data
- Central version, system access control, notifiers, and log-imbue data

Because the CPU profile briefly adds load to Central, this collector can be
turned off with `GATHER_DEBUG_DUMP=false`. Like the diagnostic bundle, it
authenticates with the admin password from the `central-htpasswd` secret
(falling back to `stackrox-admin-password`) over an `oc port-forward`, since
Central container images do not ship `curl`.

## Environment Variables

| Variable | Description | Default |
|---|---|---|
| `MUST_GATHER_SINCE` | Duration filter for logs (e.g., `8h`, `30m`) | (all logs) |
| `MUST_GATHER_SINCE_TIME` | ISO 8601 timestamp for log start | (all logs) |
| `MUST_GATHER_DIR` | Output base directory | `/must-gather` |
| `GATHER_DIAGNOSTICS` | Enable Central diagnostic endpoint collection | `true` |
| `GATHER_DIAGNOSTIC_BUNDLE` | Enable RHACS diagnostic bundle collection | `true` |
| `INSPECT_TIMEOUT` | Timeout per `oc adm inspect` call (seconds) | `120` |
| `DIAG_TIMEOUT` | Timeout per diagnostic endpoint call (seconds) | `30` |
| `DIAG_BUNDLE_TIMEOUT` | Timeout for the diagnostic bundle download (seconds) | `300` |
| `DIAG_BUNDLE_SINCE` | RFC3339 log start time for the bundle (`--since`) | `MUST_GATHER_SINCE_TIME` |
| `DIAG_BUNDLE_CLUSTERS` | Comma-separated Secured Cluster names to include (`--clusters`) | (all clusters) |
| `DIAG_BUNDLE_COMPLIANCE_OPERATOR` | Include Compliance Operator resources (`--with-compliance-operator`) | `false` |
| `DIAG_BUNDLE_DATABASE_ONLY` | Collect only Central-DB diagnostics (`--with-database-only`) | `false` |
| `GATHER_DEBUG_DUMP` | Enable Central debug dump collection | `true` |
| `DEBUG_DUMP_TIMEOUT` | Timeout for the debug dump download (seconds) | `300` |
| `DEBUG_DUMP_LOGS` | Include Central logs in the dump (`roxctl central debug dump --logs`) | `false` |

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
