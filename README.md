# Feature: RHACS Diagnostic Bundle (`acs-diagnostic-bundle`)

This branch adds the `acs-diagnostic-bundle` collector to acs-must-gather. It is
merged into `main` — see the README on `main` for the complete picture of the
codebase.

## What this branch brings to main

acs-must-gather already collects platform-specific data about the OpenShift
cluster where RHACS is running. This branch adds a second, deeper layer of data:

- **acs-diagnostic-bundle** collects deep RHACS-related data — the full diagnostic bundle produced by `roxctl central debug download-diagnostics` — from Central and every connected Secured Cluster.

## What is collected

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

## Environment Variables

| Variable | Description | Default |
|---|---|---|
| `GATHER_DIAGNOSTIC_BUNDLE` | Enable RHACS diagnostic bundle collection | `true` |
| `DIAG_BUNDLE_TIMEOUT` | Timeout for the diagnostic bundle download (seconds) | `300` |
| `DIAG_BUNDLE_SINCE` | RFC3339 log start time for the bundle (`--since`) | `MUST_GATHER_SINCE_TIME` |
| `DIAG_BUNDLE_CLUSTERS` | Comma-separated Secured Cluster names to include (`--clusters`) | (all clusters) |
| `DIAG_BUNDLE_COMPLIANCE_OPERATOR` | Include Compliance Operator resources (`--with-compliance-operator`) | `false` |
| `DIAG_BUNDLE_DATABASE_ONLY` | Collect only Central-DB diagnostics (`--with-database-only`) | `false` |
