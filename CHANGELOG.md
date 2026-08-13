# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-08-13

### Added
- **Diagnostic Bundle collection** - Comprehensive production troubleshooting bundle from `/api/extensions/diagnostics` endpoint
  - PostgreSQL deep diagnostics (pg_stat_statements, index health, analyze stats, tuple stats, active sessions)
  - Telemetry data from Central and all connected Sensors
  - Auth providers, groups, and roles with resolved permission sets
  - Notifier configurations (credentials scrubbed)
  - System configuration and delegated scanning config
  - LogImbue audit logs
  - Kubernetes resources and logs from all connected secured clusters (multi-cluster visibility)
  - Sensor Prometheus metrics from all connected clusters
- **Debug Dump collection** - Performance debugging bundle from `/debug/dump` endpoint
  - 30-second CPU profiling (pprof format)
  - Heap profile, goroutine dump, mutex profile (lock contention)
  - Prometheus metrics snapshots before and after CPU profiling
  - PostgreSQL diagnostics
- **Prometheus metrics collection** - Runtime metrics from Central's `/metrics` endpoint
- **Bundle documentation** - Created BUNDLE_CONTENTS.md with detailed breakdown of all diagnostic data collected
- **Usage guidance** - Added "Must-Gather vs roxctl" section to README explaining when to use each tool

### Changed
- Extended diagnostic collection timeouts:
  - Diagnostic Bundle: 10 minutes (can take several minutes for multi-cluster deployments)
  - Debug Dump: 3 minutes (includes 30-second CPU profiling)
- Updated README with comprehensive documentation of all collected diagnostic bundles
- Improved error handling for bundle collection with specific timeout vs failure messages

### Technical Details
- Added `collect_bundle()` function for large ZIP file downloads with custom timeouts
- Diagnostic bundles collected sequentially to avoid overloading Central
- All bundle collections fail gracefully when Central is down/unhealthy
- Kubernetes resource collection continues even if Central diagnostics fail

## [1.0.0] - 2026-08-06

### Added
- Initial release of ACS must-gather
- Operator namespace collection (pods, logs, deployments, OLM resources)
- Central Services collection (Central, Scanner V4, Scanner V4 DB, legacy Scanner)
- Secured Cluster Services collection (Sensor, Collector, Admission Controller)
- Cluster-scoped resources (CRDs, CRs, webhooks, RBAC, SCCs, nodes)
- Basic Central diagnostics (metadata, clusters, upgrade status, database status)
- Debug endpoints (goroutine dump, heap profile)
- Time-bounded log collection via `MUST_GATHER_SINCE` and `MUST_GATHER_SINCE_TIME`
- Parallel collection of all subsystems
- OpenShift-specific resource collection (Routes, SCCs)

[1.1.0]: https://github.com/Reaper-2021/acs-must-gather/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/Reaper-2021/acs-must-gather/releases/tag/v1.0.0
