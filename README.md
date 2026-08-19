# Feature: Advanced ACS Diagnostics (`advanced-acs-diagnostics/`)

This branch adds the advanced ACS diagnostics layer to acs-must-gather. It was
merged into `main` via [PR #13](https://github.com/Reaper-2021/acs-must-gather/pull/13)
— see the README on `main` for the complete picture of the codebase.

## What this branch brings to main

acs-must-gather already collects platform data, the RHACS diagnostic bundle, and
Central's debug dump — the officially-supported layers. This branch adds an
**advanced layer collected in addition to** those, targeting data they cannot
provide — most importantly data that does **not** depend on Central being
reachable. Each sub-collector is best-effort and isolated; a failure in this
layer never affects the rest of the must-gather. Disable the whole layer with
`GATHER_ADVANCED=false`. All future advanced collectors land here via the
`gather_advanced` orchestrator.

## What is collected

Extracted into the `advanced-acs-diagnostics/` folder.

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
| `GATHER_ADVANCED` | Enable the advanced ACS diagnostics layer | `true` |
| `GATHER_ADV_SECURED_CLUSTER` | Enable Central-independent secured-cluster collection | `true` |
| `GATHER_ADV_TLS_CERTS` | Enable the TLS certificate expiry report | `true` |
| `GATHER_ADV_FORENSICS` | Enable crash & upgrade forensics collection | `true` |
| `ADV_SC_TIMEOUT` | Timeout per secured-cluster endpoint call (seconds) | `DIAG_TIMEOUT` (`30`) |
| `ADV_FORENSICS_TIMEOUT` | Timeout per forensics call (seconds) | `DIAG_TIMEOUT` (`30`) |
