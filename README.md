# acs-must-gather — Scanner V4 health advanced collector

This branch is the historical record of one feature: the **Central-independent
Scanner V4 health advanced collector**. It contains only the files this feature
added or changed. For the complete, up-to-date project — every collector, the
Dockerfile, and full documentation — see
[`main`](https://github.com/Reaper-2021/acs-must-gather/tree/main).

## What this feature adds

A best-effort sub-collector in the advanced ACS diagnostics layer
(`gather_advanced_scanner_v4`), launched by the `gather_advanced` orchestrator
and gated by `GATHER_ADV_SCANNER_V4` (default `true`).

- **`scanner-v4/`** — **Central-independent** Scanner V4 triage, collected
  directly from the indexer / matcher / db pods. Includes a pod-status table
  (phase / ready / restarts / last-state / image), each component's
  `/health/readiness` (HTTPS 9443) and Prometheus `/metrics` (9091, best-effort —
  secure metrics may need a client cert, in which case an `.error` is written),
  vulnerability-updater / definitions markers grep'd from the component logs, and
  `oc describe` for the indexer / matcher / db deployments. Surfaces stuck
  vulnerability updates and never-ready or crash-looping Scanner V4 components
  that the Central-focused bundle misses. Reached over `oc port-forward`.

### Supporting changes

- The port-forward + curl helper is now a shared `collect_via_pf` in
  `common.sh`, reused by both `gather_advanced_secured_cluster` and the new
  Scanner V4 collector.
- The offline analyzer (`analysis/acs-analyze`) gains a Scanner V4 check that
  warns on not-ready components or restart churn (silent when Scanner V4 is
  absent), covered by `tests/test_analyze.py`.

## Environment Variables

| Variable | Description | Default |
|---|---|---|
| `GATHER_ADV_SCANNER_V4` | Enable Central-independent Scanner V4 health collection | `true` |
| `ADV_SCANNER_V4_TIMEOUT` | Timeout per Scanner V4 endpoint call (seconds) | `DIAG_TIMEOUT` (`30`) |
