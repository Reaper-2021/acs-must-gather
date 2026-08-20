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
  probe/driver type (`COLLECTION_METHOD`) and pod state, and a grep'd
  connectivity/certificate summary from the Sensor log. Reached over
  `oc port-forward`, which can also read the loopback-only debug servers.
- **`tls-certs/`** — an X.509 expiry report (`cert-expiry-summary.txt`) for the
  RHACS service certificates. `oc adm inspect` redacts secrets, so expired or
  mismatched certs are otherwise invisible. **Only public certificate material
  is read** (private keys are never decoded), and certs expiring within 30 days
  are flagged.
- **`crash-upgrade-forensics/`** — previous-container logs for restarted
  containers, `oc describe pod` output (OOMKilled / FailedScheduling), the
  `sensor-upgrader` deployment / logs / RBAC, and Central's Administration Events
  feed (best-effort; needs Central).

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
| `ADV_SC_TIMEOUT` | Timeout per secured-cluster endpoint call (seconds) | `DIAG_TIMEOUT` (`30`) |
| `ADV_FORENSICS_TIMEOUT` | Timeout per forensics call (seconds) | `DIAG_TIMEOUT` (`30`) |

## Analyzing an advanced diagnostics bundle

This is a step-by-step guide to reading the `advanced-acs-diagnostics/` folder and
deciding whether a Secured Cluster is healthy. It assumes you have already
extracted a must-gather and are sitting in the image sub-directory (the one named
`quay-io-...-acs-must-gather-sha256-...`).

### Prerequisites (all free, no cluster access needed)

- **`go`** — provides `go tool pprof`, used to read the `*.pb.gz` profiles. (Or
  install the standalone `pprof`: `go install github.com/google/pprof@latest`.)
- **`graphviz`** — only needed for the graphical/flame-graph views of pprof
  (`brew install graphviz` / `dnf install graphviz`). Text views work without it.
- **`jq`** — for the `*.json` files.

Set a shell variable to the folder so the examples below copy-paste cleanly:

```sh
ADV="advanced-acs-diagnostics"
```

### Step 0 — Orient yourself

```
advanced-acs-diagnostics/
├── README.txt                      # what each collector is
├── secured-cluster-local/<ns>/     # Sensor/Collector/Admission, collected WITHOUT Central
├── tls-certs/                      # certificate expiry report
└── crash-upgrade-forensics/        # crash + upgrade root-cause artifacts
```

First, sanity-check the run itself. A healthy collection has **no `.error` files**:

```sh
find "$ADV" -name '*.error'          # expect: no output
```

A `.error` file is not fatal — each collector is best-effort — but it tells you
which endpoint was unreachable (often itself a finding: e.g. a Sensor `.error`
for every port means the Sensor pod was not actually running).

A `sensor-clusterentities-state.json.skipped` file is **normal** — that store is
only served when Sensor runs with `ROX_DEBUG_CLUSTER_ENTITIES_STORE=true`.

---

### Step 1 — Sensor memory: `secured-cluster-local/<ns>/sensor-heap.pb.gz`

**What it stores:** a sampled Go heap profile (a gzip-compressed protobuf) — a
snapshot of Sensor's live memory at collection time, broken down by the call
stack that allocated it. It holds four measurements per allocation site:
`inuse_space`/`inuse_objects` (memory **live right now**) and
`alloc_space`/`alloc_objects` (memory **ever allocated**, i.e. GC churn). It does
**not** contain object contents — no secrets or payloads.

**Simplest examples (start here).** The `.pb.gz` is just a gzipped protobuf — you
never unzip it yourself; `go tool pprof` reads it directly, fully offline (nothing
here touches the cluster). If you only remember three commands:

```sh
HEAP="$ADV/secured-cluster-local/stackrox/sensor-heap.pb.gz"

# 1. How much memory is live in total, and what is using the most? (top 10)
go tool pprof -inuse_space -top -nodecount=10 "$HEAP"

# 2. Show the same thing as a picture (needs graphviz)
go tool pprof -inuse_space -web "$HEAP"

# 3. Zoom in on one function by name (e.g. anything matching "Unmarshal")
go tool pprof -inuse_space -peek Unmarshal "$HEAP"
```

(Command 3 uses `-peek`, not `-list`: `-peek` needs only the profile, while the
source-line `-list` view also needs the matching Sensor binary — see the note at
the end of this step.)

Reading command 1: the header line (`... of 189.15MB total`) is the live heap; the
first column (`flat`) is memory held by that function itself, `cum` is it plus
everything it calls. Biggest `flat` at the top = your top memory consumer. The
detailed steps below build on exactly these commands.

**Step 1a — who is using memory right now:**

```sh
go tool pprof -inuse_space -top -nodecount=15 "$ADV/secured-cluster-local/stackrox/sensor-heap.pb.gz"
```

Example output from a healthy Sensor:

```
Type: inuse_space
Showing nodes accounting for 137.81MB, 72.86% of 189.15MB total
      flat  flat%   sum%        cum   cum%
   59.27MB 31.34% 31.34%    59.27MB 31.34%  go.uber.org/zap/zapcore.newCounters
   15.50MB  8.20% 39.53%    23.51MB 12.43%  ...json.(*decodeState).objectInterface
    9.50MB  5.02% 44.56%       25MB 13.22%  storage.(*ImageScan).UnmarshalVT
    9.50MB  5.02% 49.58%       15MB  7.93%  storage.(*NetworkEntityInfo).UnmarshalVT
    7.75MB  4.10% 53.68%     7.75MB  4.10%  sensor/common/externalsrcs.(*handlerImpl).saveEntitiesNoLock
```

**How to read it:**
- `189 MB total` live is normal for a Sensor. Compare against the pod's memory
  limit (see `crash-upgrade-forensics/<ns>/describe-pods.txt`): if live heap is
  near the limit, OOMKills are imminent.
- The top consumers here are logging counters and protobuf/JSON unmarshaling of
  `ImageScan` / `NetworkEntityInfo` — expected for a Sensor processing image
  scans and network flows. A single unexpected function holding a large,
  ever-growing share is the red flag.

**Step 1b — interactive exploration** (drill into a suspect function):

```sh
go tool pprof "$ADV/secured-cluster-local/stackrox/sensor-heap.pb.gz"
(pprof) top20              # biggest consumers
(pprof) tree saveEntities  # callers/callees of a function
(pprof) peek Unmarshal     # who calls anything matching "Unmarshal"
(pprof) web                # opens a graph in the browser (needs graphviz)
```

**Step 1c — leak detection (the most valuable use).** A single snapshot cannot
prove a leak; a *trend* can. Collect two must-gathers a few minutes apart and
diff them:

```sh
go tool pprof -inuse_space -diff_base OLD/sensor-heap.pb.gz NEW/sensor-heap.pb.gz
```

Any node whose memory keeps **growing** across snapshots (especially in
StackRox code) is a leak candidate. Flat or fluctuating = healthy churn.

> Function names are embedded, so `top`/`tree` work out of the box. Source-line
> view (`list <fn>`) needs the matching Sensor binary — identify it by the
> **Build ID** printed at the top of the profile.

---

### Step 2 — Sensor concurrency: `sensor-goroutine.txt`

**What it stores:** a full text dump of every goroutine (Go's lightweight
threads) and its current stack, from `/debug/goroutine?debug=2`.

**Step 2a — count goroutines** (the single best liveness number):

```sh
grep -c '^goroutine ' "$ADV/secured-cluster-local/stackrox/sensor-goroutine.txt"
```

A healthy Sensor is typically a few hundred to low thousands. **Tens of
thousands, or a number that keeps climbing across snapshots, means a goroutine
leak** — usually a blocked channel send/receive or an un-cancelled context.

**Step 2b — find what they are stuck on** (group by top-of-stack function):

```sh
grep -A1 '^goroutine ' "$ADV/secured-cluster-local/stackrox/sensor-goroutine.txt" \
  | grep -v '^goroutine' | grep -v '^--' | sort | uniq -c | sort -rn | head
```

**Step 2c — look for long-blocked goroutines.** The dump annotates how long a
goroutine has been blocked; anything stuck for many minutes is suspicious:

```sh
grep -oE '[0-9]+ minutes' "$ADV/secured-cluster-local/stackrox/sensor-goroutine.txt" | sort -rn | head
```

---

### Step 3 — Metrics: `sensor-metrics.txt`, `admission-control-metrics.txt`, `collector-metrics.txt`

**What they store:** a one-shot scrape of each component's Prometheus `/metrics`
endpoint (plain text, `# HELP` / `# TYPE` / `metric{labels} value`).

**Step 3a — is Sensor actually talking to Central?** These counters should be
non-zero and, across two snapshots, **increasing**:

```sh
grep -E '^rox_sensor_(events|central_.*grpc|messages)' "$ADV/secured-cluster-local/stackrox/sensor-metrics.txt" | head
```

**Step 3b — Go runtime health (leak corroboration):**

```sh
grep -E '^go_goroutines|^go_memstats_heap_inuse_bytes|^process_resident_memory_bytes' \
  "$ADV/secured-cluster-local/stackrox/sensor-metrics.txt"
```

`go_goroutines` should match Step 2a; `process_resident_memory_bytes` is the RSS
you compare against the pod limit.

**Step 3c — error/drop counters** (should be low and stable):

```sh
grep -iE 'error|dropped|failed|reject' "$ADV/secured-cluster-local/stackrox/sensor-metrics.txt" | grep -vE ' 0$'
```

Anything here with a large or growing value is a live problem.

---

### Step 4 — Collector: `collector-status.txt` and `collector-pods.txt`

**What they store:** the collection driver each Collector pod is using and its
restart state (`collector-status.txt`), plus `oc get pods -o wide` for the
DaemonSet (`collector-pods.txt`).

```sh
cat "$ADV/secured-cluster-local/stackrox/collector-status.txt"
```

Example (healthy):

```
=== collector-bpdfv ===
  collectionMethod: CORE_BPF
  restartCount: 0
  lastState:
```

**How to read it:**
- `collectionMethod: CORE_BPF` (or `EBPF`) on **every** node is what you want.
- `restartCount` climbing, or a `lastState` of `Terminated`/`OOMKilled`, points to
  kernel-compatibility or memory problems on that specific node.
- Confirm there is one Collector pod per node in `collector-pods.txt`; a missing
  node means that node's runtime activity is not being observed.

---

### Step 5 — Connectivity summary: `sensor-connectivity-summary.txt`

**What it stores:** the connection/certificate-relevant lines grep'd out of the
Sensor log, so you can judge the Sensor↔Central link without reading full logs.

**Healthy** looks like a clean connect sequence:

```
Info: Connecting to Central server central.stackrox.svc:443
Info: Established connection to Central.
Info: Communication with central started.
```

**Unhealthy** — watch for these and act accordingly:

| Line contains | Likely cause |
|---|---|
| `not trusted` / `invalid trust info signature` | cert/CA mismatch → check Step 6 |
| `different Central installation` | Sensor pointed at a re-installed Central → re-issue init bundle |
| `checking central status ... failed` / repeated `Connecting to Central` | network/DNS/Central-down |
| `offline mode` | Sensor lost Central and is buffering |

---

### Step 6 — Certificates: `tls-certs/cert-expiry-summary.txt`

**What it stores:** subject/issuer/validity for every RHACS service certificate,
decoded from the TLS secrets (public cert material only — **private keys are
never read**). This is otherwise invisible because `oc adm inspect` redacts
secrets.

**Find anything not healthy in one command:**

```sh
grep -vE 'OK \(>30d' "$ADV/tls-certs/cert-expiry-summary.txt" | grep -E 'status:|==='
```

- `status: OK (>30d remaining)` on all entries → certs are fine.
- `status: WARNING - expires within 30 days` → plan a rotation now.
- `status: EXPIRED` → this is very likely your root cause; expired mTLS certs are
  the classic reason Sensor/Scanner "suddenly can't connect". Cross-reference
  with the `not trusted` line in Step 5.

---

### Step 7 — Crashes & upgrades: `crash-upgrade-forensics/`

**Step 7a — why did a container die?** `previous-logs/` holds the log of the
*previous* (crashed) instance of every container that has restarted — the single
most useful crash artifact, and one a normal must-gather does not isolate:

```sh
ls "$ADV/crash-upgrade-forensics/stackrox/previous-logs/"
tail -50 "$ADV/crash-upgrade-forensics/stackrox/previous-logs/<pod>-<container>.log"
```

**Step 7b — OOMKilled / scheduling failures:** `describe-pods.txt` carries the
container `Last State`, exit codes, and events:

```sh
grep -E 'OOMKilled|Reason|Exit Code|FailedScheduling|Back-off' \
  "$ADV/crash-upgrade-forensics/stackrox/describe-pods.txt"
```

`OOMKilled` here + a high `inuse_space` in Step 1 = raise the memory limit or
find the leak.

**Step 7c — RHACS's own view of problems:** `administration-events.json` is what
Central surfaces to admins (scan failures, integration errors, expiring tokens):

```sh
jq -r '.events[] | "\(.level)  \(.type)  \(.hint // .message)"' \
  "$ADV/crash-upgrade-forensics/administration-events.json"
```

**Step 7d — upgrade problems:** if a Sensor upgrade is stuck, look for the
`sensor-upgrader-*.log` and `upgrade-sensors-rbac.yaml` files; their absence
simply means no upgrade was in progress.

---

### Quick "is this cluster healthy?" checklist

| Check | Healthy | Where |
|---|---|---|
| No collection errors | no `.error` files | `find "$ADV" -name '*.error'` |
| Sensor↔Central connected | `Established connection to Central` | Step 5 |
| Certs valid | all `OK (>30d)` | Step 6 |
| Sensor memory sane | live heap well under pod limit | Steps 1 + 7b |
| No goroutine leak | count stable, low thousands | Step 2 |
| No crash loops | `restartCount` low, no `OOMKilled` | Steps 4 + 7b |
| Collector on every node | one `CORE_BPF`/`EBPF` pod per node | Step 4 |
| No admin-visible errors | few/no `ERROR` events | Step 7c |

If every row is green, the Secured Cluster is functioning well. The most common
real failures this bundle exposes are, in order: **expired certificates**
(Step 6), **OOMKilled components** (Steps 1 + 7b), and **Sensor↔Central
connectivity breaks** (Step 5).

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
