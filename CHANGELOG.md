# Changelog

This file helps users learn about what is new in a release of ACS Must-Gather.

Put an entry in this file if your change is user-visible and you consider it _particularly noteworthy_. Especially:
- Any changes that introduce a deprecation in functionality, OR
- Obscure side-effects that are not obviously apparent based on the PR associated with the changes.

ACS Must-Gather is a must-gather image for collecting diagnostic information from
Red Hat Advanced Cluster Security (RHACS / StackRox) deployments on OpenShift
clusters. It collects three complementary layers of data: **acs-must-gather**
(platform-specific cluster data), **acs-diagnostic-bundle** (the full
`roxctl central debug download-diagnostics` bundle), and **acs-debug-dump**
(Central's `roxctl central debug dump`, including a 30-second CPU profile).

## [1.6.0] - 2026-08-21

### Added Features

- Known-issue diagnostics under the advanced layer
  (`advanced-acs-diagnostics/platform/`). A new best-effort sub-collector,
  `gather_advanced_platform`, that captures platform scoping, storage, and
  startup forensics that map to recurring support cases but that `oc adm inspect`
  does not surface cleanly:
  - The `init-db` init-container log (current + previous) for **every** RHACS
    PostgreSQL database — `central-db`, `scanner-db`, and `scanner-v4-db` — since
    a permission error on the data volume is the classic `db-init`
    CrashLoopBackOff and the log is lost once the pod is recreated.
  - The Sensor `crs` init-container log (CRS-based cluster registration and cert
    setup — a failure there stops the Secured Cluster from registering or
    connecting).
  - Per-database Postgres migration / lock / slow-upgrade markers.
  - `oc describe pvc` (binding/provisioning events the PVC yaml does not spell
    out), the OpenShift internal-registry CA configmap
    (`image-registry-certificates`, needed to debug `x509: certificate signed by
    unknown authority` after a CA rotation), and a single chronologically-sorted
    events file per namespace.
  - Toggle with `GATHER_ADV_PLATFORM`; timeout `ADV_PLATFORM_TIMEOUT`
    (default `DIAG_TIMEOUT`, `30`).
- Cluster-scoped collection now includes a node-to-kernel matrix (OS image +
  kernel version per node) and ClusterVersion (OpenShift), StorageClasses, and
  PersistentVolumes.
- The analyzer (`analysis/acs-analyze`) gained checks for per-database `db-init`
  permission/startup failures on any RHACS database (central-db / scanner-db /
  scanner-v4-db), the Sensor duplicate-IP warning count, and distinct node
  kernel versions.

### Technical Changes

- Scanner V4 collection additionally reports matcher/indexer memory tuning
  (`GOMEMLIMIT`) and the component `Service` / `Endpoints`; secured-cluster
  collection adds an x509 CA-rotation marker and a count of the
  `belongs to 2 or more deployments` duplicate-IP warning.

## [1.5.0] - 2026-08-21

### Added Features

- Image-CVE / vulnerability and policy-violation snapshot under the advanced
  layer (`advanced-acs-diagnostics/vuln-report/`). A new best-effort
  sub-collector, `gather_advanced_vuln_report`, pulled from Central's REST API
  (admin basic-auth over `oc port-forward`, the same mechanism as the debug
  dump). The officially-supported bundle describes Central's *health*; it does
  not carry the per-image CVE findings or the violation list a support case
  usually turns on. Includes:
  - `vuln-mgmt-workloads.json` — streaming `/v1/export/vuln-mgmt/workloads`
    (every deployment joined to its images with full CVE data, the
    machine-readable dataset the analyzer filters).
  - `image-cves.csv` — human-readable image CVEs (opens in any spreadsheet).
  - `violations.json` — policy violations, paged; and
    `alerts-summary-counts-*.json` — violation rollups by cluster / category.
  - Violations default to `ACTIVE,ATTEMPTED` to keep the bundle bounded on
    long-lived clusters — set `ADV_VULN_ALERT_STATES` for a fuller history.
  - Toggle with `GATHER_ADV_VULN_REPORT`; timeout `ADV_VULN_TIMEOUT`
    (default `300`).
- The analyzer (`analysis/acs-analyze`) now summarizes image-scan CVEs (flagging
  images with fixable critical / important findings) and policy violations by
  severity when the `vuln-report/` layer is present; pass `--image <name>` to
  drill into the per-CVE list for a specific image.

## [1.4.1] - 2026-08-21

### Technical Changes

- Hardened the image base: pinned the base image by digest and patched OS
  packages.

## [1.4.0] - 2026-08-21

### Added Features

- Offline must-gather bundle health analyzer (`analysis/acs-analyze`). A
  standalone, stdlib-only Python tool that reads an extracted must-gather and
  prints an automated, scored health report — `OK` / `WARN` / `FAIL` / `SKIP` —
  entirely offline, never contacting a cluster. It exits non-zero if any check
  `FAIL`s, so it is CI / scripting friendly. New `make test` and `make analyze`
  targets.
- Central-independent Scanner V4 health collection under the advanced layer
  (`advanced-acs-diagnostics/scanner-v4/`). A new best-effort sub-collector,
  `gather_advanced_scanner_v4`, collected directly from the indexer / matcher /
  db pods: a pod-status table (phase / ready / restarts / last-state / image),
  each component's `/health/readiness` (HTTPS 9443) and Prometheus `/metrics`
  (9091, best-effort), vulnerability-updater / definitions markers grep'd from
  the component logs, and `oc describe` for the indexer / matcher / db
  deployments. Toggle with `GATHER_ADV_SCANNER_V4`; timeout
  `ADV_SCANNER_V4_TIMEOUT` (default `DIAG_TIMEOUT`, `30`).

### Technical Changes

- The shared `collect_via_pf` port-forward helper was hoisted into `common.sh`
  so both the Scanner V4 collector and later collectors reuse it.

### Note

- The analyzer (`analysis/acs-analyze`) is host-side tooling and is intentionally
  **not** copied into the image (the Dockerfile only `COPY`s
  `collection-scripts/*`), so analyzer-only changes do not require an image
  rebuild.

## [1.3.0] - 2026-08-19

### Added Features

- Advanced ACS diagnostics layer (`advanced-acs-diagnostics/`). A new best-effort
  layer collected in addition to the officially-supported diagnostic bundle and
  debug dump, targeting data those layers cannot provide. It is isolated — a
  failure here never affects the rest of the must-gather — and can be turned off
  with `GATHER_ADVANCED=false`. All future advanced collectors will land here.
  It contains three independent collectors:
  - **Secured-cluster local diagnostics** (`secured-cluster-local/`): Sensor,
    Collector, and Admission Controller data collected directly from the pods
    **without requiring Central or an admin login** — the data that is missing
    when Sensor cannot reach Central. Includes Sensor pprof (heap/goroutine) and
    its cluster-entities store, Prometheus `/metrics` from Sensor / Admission
    Controller / Collector, the Collector probe/driver type and pod state, and a
    connectivity/certificate summary grep'd from the Sensor log. Toggle with
    `GATHER_ADV_SECURED_CLUSTER`.
  - **TLS certificate expiry report** (`tls-certs/`): decodes only the public
    certificate material from RHACS TLS secrets (private keys are never read) and
    reports subject/issuer/validity, flagging certs that expire within 30 days.
    This is invisible in a normal must-gather because `oc adm inspect` redacts
    secrets. Requires `openssl` (now installed in the image). Toggle with
    `GATHER_ADV_TLS_CERTS`.
  - **Crash & upgrade forensics** (`crash-upgrade-forensics/`): previous-container
    logs for restarted containers, `oc describe pod` output, the `sensor-upgrader`
    deployment/logs/RBAC, and Central's Administration Events (best-effort).
    Toggle with `GATHER_ADV_FORENSICS`.

### Removed Features

### Deprecated Features

### Technical Changes

- The image now installs `openssl` (used by the TLS certificate expiry report).

## [1.2.0] - 2026-08-15

### Added Features

- #10: Central debug dump collection (`acs-debug-dump`). Downloads Central's debug
  dump from the `/debug/dump` endpoint (equivalent to `roxctl central debug dump`)
  and extracts it into the `acs-debug-dump/` folder so it is browsable within the
  must-gather. It is the deepest, Central-focused diagnostic layer and includes:
  - A 30-second CPU profile, plus heap, goroutine, and mutex profiles
  - Two Prometheus metrics passes and Central-DB (PostgreSQL) data
  - Central version, system access control, notifiers, and log-imbue data
- #10: Enabled by default via `GATHER_DEBUG_DUMP`. Because the CPU profile briefly
  adds load to Central, this collector can be turned off with `GATHER_DEBUG_DUMP=false`.
- #10: New environment variables: `GATHER_DEBUG_DUMP`, `DEBUG_DUMP_TIMEOUT`, and
  `DEBUG_DUMP_LOGS`.

### Technical Changes

- #10: Like the diagnostic bundle, the debug dump authenticates with the admin
  password from the `central-htpasswd` secret (falling back to
  `stackrox-admin-password`) over an `oc port-forward`, since Central container
  images do not ship `curl`.

## [1.1.0] - 2026-08-14

### Added Features

- #7: RHACS diagnostic bundle collection (`acs-diagnostic-bundle`). The full
  diagnostic bundle produced by `roxctl central debug download-diagnostics`,
  downloaded from Central's `/api/extensions/diagnostics` endpoint and unpacked
  into the `acs-diagnostic-bundle/` folder. It contains deep RHACS data from
  Central and every connected Secured Cluster, including:
  - Build versions and Central-DB (PostgreSQL) diagnostics (`pg_stat` statistics)
  - Prometheus metrics and heap / goroutine / mutex profiles
  - System configuration, scrubbed auth providers, roles, and notifiers
  - Telemetry data
  - Kubernetes introspection (resource manifests, pod logs, events) from Central
    and each Secured Cluster
- #7: New environment variables: `GATHER_DIAGNOSTIC_BUNDLE`, `DIAG_BUNDLE_TIMEOUT`,
  `DIAG_BUNDLE_SINCE`, `DIAG_BUNDLE_CLUSTERS`, `DIAG_BUNDLE_COMPLIANCE_OPERATOR`,
  and `DIAG_BUNDLE_DATABASE_ONLY`.

### Technical Changes

- #7: Central serves the diagnostics endpoint with admin authentication only. The
  password is read from the `central-htpasswd` secret (falling back to
  `stackrox-admin-password`), and Central is reached over an `oc port-forward`
  since Central container images do not ship `curl`.

## [1.0.0] - 2026-08-14

### Added Features

- Initial release of the ACS Must-Gather image (`acs-must-gather`) collecting
  platform-specific data about the OpenShift cluster where RHACS is running.
- Operator: RHACS operator namespace (pods, logs, deployments, events) and OLM
  resources (ClusterServiceVersion, Subscription, InstallPlan).
- Central Services: Central deployment, Central DB, Scanner V4 (indexer, matcher,
  database), legacy Scanner (if present), ConfigMaps, Services, Routes,
  NetworkPolicies, PVCs, and HPAs.
- Secured Cluster Services: Sensor deployment, Collector DaemonSet, Admission
  Controller deployment, and NetworkPolicies.
- Cluster-Scoped Resources: ACS CRDs and CR instances (Central, SecuredCluster,
  SecurityPolicy), Validating/Mutating WebhookConfigurations, ClusterRoles and
  ClusterRoleBindings, SecurityContextConstraints (OpenShift), and node summary.
- #6: Central Diagnostics via port-forward + admin authentication:
  - `/v1/metadata` — Central version and build info
  - `/v1/clusters` — connected cluster list
  - `/v1/centralhealth/upgradestatus` — upgrade/rollback status
  - `/v1/database/status` — database health
  - `/debug/goroutine` — goroutine stack dump
  - `/debug/heap` — heap memory profile
- Time-bounded collection via `MUST_GATHER_SINCE` and `MUST_GATHER_SINCE_TIME`.
- Environment variables: `MUST_GATHER_SINCE`, `MUST_GATHER_SINCE_TIME`,
  `MUST_GATHER_DIR`, `GATHER_DIAGNOSTICS`, `INSPECT_TIMEOUT`, and `DIAG_TIMEOUT`.
