# acs-must-gather — known-issue diagnostics

This branch is the historical record of one feature: a set of **known-issue
diagnostics** derived from real RHACS customer support history (KCS / Jira / RFE
analysis). It contains only the files this feature added or changed. For the
complete, up-to-date project — every collector, the Dockerfile, and full
documentation — see
[`main`](https://github.com/Reaper-2021/acs-must-gather/tree/main).

## What this feature adds

Targeted signals and out-of-namespace objects that `oc adm inspect` does not
surface cleanly, each mapped to a recurring known issue.

### New advanced collector — `gather_advanced_platform` → `platform/`

Platform scoping, storage, and startup forensics. Gated by `GATHER_ADV_PLATFORM`
(default `true`), timeout `ADV_PLATFORM_TIMEOUT`. Launched by the
`gather_advanced` orchestrator; best-effort and isolated like every advanced
sub-collector.

- the `init-db` init-container log (current + previous) for **every** RHACS
  PostgreSQL database — `central-db`, `scanner-db`, and `scanner-v4-db` — since a
  permission error on the data volume is the classic `db-init` CrashLoopBackOff
  and the log is lost once the pod is recreated. Init-container names are
  discovered dynamically via jsonpath; each DB is resolved as statefulset-or-deployment.
- the Sensor `crs` init-container log — CRS-based cluster registration and cert
  setup; a failure there stops the Secured Cluster from registering or connecting.
- per-database Postgres migration / lock / slow-upgrade markers (routine
  checkpoint / vacuum background activity is deliberately excluded so the file
  carries signal, not noise).
- `oc describe pvc` — binding/provisioning events the PVC yaml does not spell out.
- the OpenShift internal-registry CA configmap (`image-registry-certificates`),
  which lives outside the ACS namespaces and is needed to debug
  `x509: certificate signed by unknown authority` after a CA rotation.
- a single chronologically-sorted events file per namespace.

### Extended collectors

- **`gather_cluster_scoped`** — a node-to-kernel matrix (OS image + kernel
  version per node), plus ClusterVersion (OpenShift), StorageClasses, and
  PersistentVolumes — Collector driver/kernel mismatch context.
- **`gather_advanced_secured_cluster`** — the x509 `certificate signed by
  unknown authority` marker (CA-rotation signature) and a `belongs to 2 or more
  deployments` duplicate-IP warning count (a known Sensor memory-growth driver).
- **`gather_advanced_scanner_v4`** — matcher / indexer memory tuning
  (requests / limits + `GOMEMLIMIT`, to correlate matcher OOMs during VEX feed
  updates) and the component `Service` / `Endpoints`.

### Analyzer — `analysis/acs-analyze`

- `check_db_init` — reports `db-init` permission/startup failures on each RHACS
  database independently (central-db / scanner-db / scanner-v4-db), and the
  Sensor `crs` cluster-registration / cert failure.
- `check_sensor_ip_dup` — the Sensor duplicate-IP warning count.
- `check_node_kernels` — distinct node kernel versions.
- flags x509 CA-rotation breakage in the connectivity check.
- covered by `tests/test_analyze.py`.

## Environment Variables

| Variable | Description | Default |
|---|---|---|
| `GATHER_ADV_PLATFORM` | Enable platform scoping, storage & startup forensics (db-init log, PVC describe, registry CA, sorted events) | `true` |
| `ADV_PLATFORM_TIMEOUT` | Timeout per platform-forensics log call (seconds) | `DIAG_TIMEOUT` (`30`) |
