# Feature: RHACS Central Debug Dump (`acs-debug-dump`)

This branch adds the `acs-debug-dump` collector to acs-must-gather. It was
merged into `main` via [PR #10](https://github.com/Reaper-2021/acs-must-gather/pull/10)
— see the README on `main` for the complete picture of the codebase.

## What this branch brings to main

acs-must-gather already collects platform data and the RHACS diagnostic bundle.
This branch adds the deepest, Central-focused layer:

- **acs-debug-dump** collects Central's debug dump — the deepest, Central-focused profiling data produced by `roxctl central debug dump`, including a 30-second CPU profile.

## What is collected

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

## Environment Variables

| Variable | Description | Default |
|---|---|---|
| `GATHER_DEBUG_DUMP` | Enable Central debug dump collection | `true` |
| `DEBUG_DUMP_TIMEOUT` | Timeout for the debug dump download (seconds) | `300` |
| `DEBUG_DUMP_LOGS` | Include Central logs in the dump (`roxctl central debug dump --logs`) | `false` |
