# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v1.2.0] - 2026-08-14

### Added
- **Diagnostic Bundle collection (opt-in)** via Central's `/api/extensions/diagnostics` endpoint (#1).
  - New script: `collection-scripts/gather_diagnostic_bundle`.
  - Enable with `GATHER_DIAGNOSTIC_BUNDLE=true` (default: `false`).
  - Collects PostgreSQL deep diagnostics, telemetry, auth configuration, and multi-cluster data.
  - Options: `DIAGNOSTIC_BUNDLE_CLUSTER`, `DIAGNOSTIC_BUNDLE_DATABASE_ONLY`, `DIAGNOSTIC_BUNDLE_SINCE`, `DIAGNOSTIC_BUNDLE_TIMEOUT`, `DIAGNOSTIC_BUNDLE_COMPLIANCE_OPERATOR`.
  - See `FEATURE_DIAGNOSTIC_BUNDLE.md` for details.

## [v1.1.0] - 2026-08-14

### Added
- **Debug Dump collection (opt-in)** via Central's `/debug/dump` endpoint (#2).
  - New script: `collection-scripts/gather_debug_dump`.
  - Enable with `GATHER_DEBUG_DUMP=true` (default: `false`).
  - Collects a 30-second CPU profile, heap/goroutine/mutex profiles, dual Prometheus snapshots, PostgreSQL diagnostics, and configuration data.
  - Options: `DEBUG_DUMP_LOGS`, `DEBUG_DUMP_TELEMETRY`, `DEBUG_DUMP_TIMEOUT`.
  - See `FEATURE_DEBUG_DUMP.md` for details.

## [v1.0.0] - 2026-08-06

### Added
- Initial release: OpenShift must-gather image for RHACS/StackRox diagnostics.
- Collects operator, Central services, secured cluster services, and cluster-scoped resources.
- Central diagnostic endpoints, time-bounded log collection, and testing infrastructure.

[v1.2.0]: https://github.com/Reaper-2021/acs-must-gather/releases/tag/v1.2.0
[v1.1.0]: https://github.com/Reaper-2021/acs-must-gather/releases/tag/v1.1.0
[v1.0.0]: https://github.com/Reaper-2021/acs-must-gather/releases/tag/v1.0.0
