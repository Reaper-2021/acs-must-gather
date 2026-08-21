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
- Node summary and a node-to-kernel matrix (OS image + kernel version per node)
- ClusterVersion (OpenShift), StorageClasses, and PersistentVolumes

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

### Advanced ACS Diagnostics

Extracted into the `advanced-acs-diagnostics/` folder. This is an **advanced
layer collected in addition to** the officially-supported diagnostic bundle and
debug dump above. It targets data those layers cannot provide — most importantly
data that does **not** depend on Central being reachable. Each sub-collector is
best-effort and isolated; a failure in this layer never affects the rest of the
must-gather. Disable the whole layer with `GATHER_ADVANCED=false`.

- **`secured-cluster-local/`** — Sensor, Collector, and Admission Controller data
  collected **directly from the pods, without requiring Central or an admin
  login** — exactly what is missing when Sensor cannot reach Central. Includes
  Sensor's pprof heap/goroutine dumps and its cluster-entities store, Prometheus
  `/metrics` from Sensor / Admission Controller / Collector, the Collector
  probe/driver type (`COLLECTION_METHOD`) and pod state, a grep'd
  connectivity/certificate summary from the Sensor log (including
  `certificate signed by unknown authority`, the CA-rotation signature), and a
  count of the `belongs to 2 or more deployments` duplicate-IP warning (a known
  Sensor memory-growth driver). Reached over `oc port-forward`, which can also
  read the loopback-only debug servers.
- **`tls-certs/`** — an X.509 expiry report (`cert-expiry-summary.txt`) for the
  RHACS service certificates. `oc adm inspect` redacts secrets, so expired or
  mismatched certs are otherwise invisible. **Only public certificate material
  is read** (private keys are never decoded), and certs expiring within 30 days
  are flagged.
- **`crash-upgrade-forensics/`** — previous-container logs for restarted
  containers, `oc describe pod` output (OOMKilled / FailedScheduling), the
  `sensor-upgrader` deployment / logs / RBAC, and Central's Administration Events
  feed (best-effort; needs Central).
- **`scanner-v4/`** — **Central-independent** Scanner V4 triage, collected
  directly from the indexer / matcher / db pods. Includes a pod-status table
  (phase / ready / restarts / last-state / image), each component's
  `/health/readiness` (HTTPS 9443) and Prometheus `/metrics` (9091, best-effort —
  secure metrics may need a client cert, in which case an `.error` is written),
  vulnerability-updater / definitions markers grep'd from the component logs,
  `oc describe` for the indexer / matcher / db deployments, a memory-tuning
  summary (requests / limits + `GOMEMLIMIT`, to correlate matcher OOMs during
  VEX feed updates), and the component `Service` / `Endpoints` (a matcher or
  indexer that never becomes ready shows up as a Service with no ready
  endpoints). Surfaces stuck vulnerability updates and never-ready or
  crash-looping Scanner V4 components that the Central-focused bundle misses.
  Reached over `oc port-forward`.
- **`vuln-report/`** — an image-scan / CVE and policy-violation snapshot pulled
  from Central's REST API (admin basic-auth over `oc port-forward`, the same
  mechanism as the debug dump). The officially-supported bundle describes
  Central's *health*; it does not carry the per-image CVE findings or the
  violation list a support case usually turns on. Includes
  `vuln-mgmt-workloads.json` (streaming `/v1/export/vuln-mgmt/workloads` — every
  deployment joined to its images with full CVE data, the machine-readable
  dataset the analyzer filters), `image-cves.csv` (human-readable image CVEs,
  opens in any spreadsheet), `violations.json` (policy violations, paged), and
  `alerts-summary-counts-*.json` (violation rollups by cluster / category).
  Violations default to `ACTIVE,ATTEMPTED` to keep the bundle bounded on
  long-lived clusters — set `ADV_VULN_ALERT_STATES` for a fuller history.
- **`platform/`** — platform scoping, storage, and startup forensics that map to
  recurring support cases but that `oc adm inspect` does not surface cleanly: the
  `init-db` init-container log (current + previous) for **every** RHACS
  PostgreSQL database — `central-db`, `scanner-db`, and `scanner-v4-db` — since a
  permission error on the data volume is the classic `db-init` CrashLoopBackOff
  and the log is lost once the pod is recreated, the Sensor `crs` init-container
  log (CRS-based cluster registration and cert setup — a failure there stops the
  Secured Cluster from registering or connecting), per-database Postgres
  migration / lock / slow-upgrade markers, `oc describe pvc` (binding/provisioning events
  the PVC yaml does not spell out), the OpenShift internal-registry CA configmap
  (`image-registry-certificates`, which lives outside the ACS namespaces and is
  needed to debug `x509: certificate signed by unknown authority` after a CA
  rotation), and a single chronologically-sorted events file per namespace.

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
| `GATHER_ADVANCED` | Enable the advanced ACS diagnostics layer | `true` |
| `GATHER_ADV_SECURED_CLUSTER` | Enable Central-independent secured-cluster collection | `true` |
| `GATHER_ADV_TLS_CERTS` | Enable the TLS certificate expiry report | `true` |
| `GATHER_ADV_FORENSICS` | Enable crash & upgrade forensics collection | `true` |
| `GATHER_ADV_SCANNER_V4` | Enable Central-independent Scanner V4 health collection | `true` |
| `GATHER_ADV_VULN_REPORT` | Enable the image-CVE / violation snapshot from Central's API | `true` |
| `GATHER_ADV_PLATFORM` | Enable platform scoping, storage & startup forensics (db-init log, PVC describe, registry CA, sorted events) | `true` |
| `ADV_SC_TIMEOUT` | Timeout per secured-cluster endpoint call (seconds) | `DIAG_TIMEOUT` (`30`) |
| `ADV_FORENSICS_TIMEOUT` | Timeout per forensics call (seconds) | `DIAG_TIMEOUT` (`30`) |
| `ADV_SCANNER_V4_TIMEOUT` | Timeout per Scanner V4 endpoint call (seconds) | `DIAG_TIMEOUT` (`30`) |
| `ADV_VULN_TIMEOUT` | Timeout per vuln-report API call (seconds) | `300` |
| `ADV_VULN_ALERT_STATES` | Violation states to snapshot (comma-separated) | `ACTIVE,ATTEMPTED` |
| `ADV_PLATFORM_TIMEOUT` | Timeout per platform-forensics log call (seconds) | `DIAG_TIMEOUT` (`30`) |

## Analyzing a bundle

`analysis/acs-analyze` reads an extracted must-gather and prints an automated
health report — the "is this cluster healthy?" checklist, scored. It runs
entirely offline against the extracted files and never contacts a cluster.

```sh
# point it at the extracted must-gather (root, or the image sub-directory)
analysis/acs-analyze path/to/must-gather.local.XXXX
# or via make
make analyze BUNDLE=path/to/must-gather.local.XXXX
```

It reports Central version / license, Central-DB availability, connected
clusters (collection method + version skew), distinct node kernel versions, and
— when the advanced layer is present — collection errors, Sensor↔Central
connectivity (including x509 CA-rotation breakage), TLS-cert expiry,
Sensor/Central heap and goroutine counts, Collector status, Scanner V4
readiness / restart churn, `db-init` permission/startup failures on any RHACS
database (central-db / scanner-db / scanner-v4-db), the
Sensor duplicate-IP warning count, admin events, and OOMKilled / restarting
pods. The heap check reads each component's pod memory
limit from its manifest and warns on the real percentage used (`WARN` ≥75%,
`FAIL` ≥90%). When the `vuln-report/` layer is present it also summarizes
image-scan CVEs (flagging images with fixable critical / important findings) and
policy violations by severity; pass `--image <name>` to drill into the per-CVE
list for a specific image. Each check is `OK` / `WARN` / `FAIL` / `SKIP`; the
process exits non-zero if any check `FAIL`s, so it is CI/scripting friendly.

Requires `python3` (stdlib only). The heap checks use `go tool pprof` when `go`
is installed; without it they `SKIP`.

## Building

```sh
make build
make push
```

## Linting

```sh
make lint
```

Requires [shellcheck](https://www.shellcheck.net/) (and `python3` for the
analyzer syntax check).

## Testing

```sh
make test
```

Runs the analyzer test suite (`tests/test_analyze.py`, stdlib `unittest`).
