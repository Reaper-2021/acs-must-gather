# acs-must-gather — offline bundle health analyzer

This branch is the historical record of one feature: the **offline
must-gather bundle health analyzer** (`analysis/acs-analyze`). It contains only
the files this feature added or changed. For the complete, up-to-date project —
every collector, the Dockerfile, and full documentation — see
[`main`](https://github.com/Reaper-2021/acs-must-gather/tree/main).

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
clusters (collection method + version skew), and — when the advanced layer is
present — collection errors, Sensor↔Central connectivity, TLS-cert expiry,
Sensor/Central heap and goroutine counts, Collector status, admin events, and
OOMKilled / restarting pods. The heap check reads each component's pod memory
limit from its manifest and warns on the real percentage used (`WARN` ≥75%,
`FAIL` ≥90%). Each check is `OK` / `WARN` / `FAIL` / `SKIP`; the process exits
non-zero if any check `FAIL`s, so it is CI/scripting friendly.

Requires `python3` (stdlib only). The heap checks use `go tool pprof` when `go`
is installed; without it they `SKIP`.

## Testing

```sh
make test
```

Runs the analyzer test suite (`tests/test_analyze.py`, stdlib `unittest`).
