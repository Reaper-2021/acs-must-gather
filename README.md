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

### Optional: Debug Dump (Experimental)
To collect Central's debug dump with CPU profiling for performance debugging:

```sh
oc adm must-gather \
  --image=quay.io/rhn_support_shaising/acs-must-gather:latest \
  -- /usr/bin/gather \
  GATHER_DEBUG_DUMP=true
```

**Advanced Options:**
```sh
# With Central logs included
oc adm must-gather \
  --image=quay.io/rhn_support_shaising/acs-must-gather:latest \
  -- /usr/bin/gather \
  GATHER_DEBUG_DUMP=true \
  DEBUG_DUMP_LOGS=true

# With telemetry data (Central + all Sensors)
oc adm must-gather \
  --image=quay.io/rhn_support_shaising/acs-must-gather:latest \
  -- /usr/bin/gather \
  GATHER_DEBUG_DUMP=true \
  DEBUG_DUMP_TELEMETRY=2
```

**Note**: Requires Central running and admin password in Secret. Includes 30-second CPU profiling. Collection takes 1-3 minutes.

**Comparison with Official Methods:**
| Method | Best For | Limitations |
|--------|----------|-------------|
| **acs-must-gather** | Performance issues needing full context (profiles + K8s + operator) | Slower, requires cluster admin |
| **roxctl CLI** | Quick CPU/heap profiling with external access | Requires route, no K8s resources |
| **Direct API** | Manual debugging, rapid iteration | Manual, multi-step |

See `FEATURE_DEBUG_DUMP.md` for complete comparison and pprof analysis guide.

## Environment Variables

### General Collection

| Variable | Description | Default |
|---|---|---|
| `MUST_GATHER_SINCE` | Duration filter for logs (e.g., `8h`, `30m`) | (all logs) |
| `MUST_GATHER_SINCE_TIME` | ISO 8601 timestamp for log start | (all logs) |
| `MUST_GATHER_DIR` | Output base directory | `/must-gather` |
| `GATHER_DIAGNOSTICS` | Enable Central diagnostic endpoint collection | `true` |
| `INSPECT_TIMEOUT` | Timeout per `oc adm inspect` call (seconds) | `120` |
| `DIAG_TIMEOUT` | Timeout per diagnostic endpoint call (seconds) | `30` |

### Debug Dump (Optional)

| Variable | Description | Default |
|---|---|---|
| `GATHER_DEBUG_DUMP` | Enable debug dump collection (CPU/heap profiling) | `false` |
| `DEBUG_DUMP_TIMEOUT` | Collection timeout (seconds) | `180` (3 min) |
| `DEBUG_DUMP_LOGS` | Include Central logs in dump | `false` |
| `DEBUG_DUMP_TELEMETRY` | Include telemetry (0=none, 1=Central, 2=Central+Sensors) | (none) |

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
