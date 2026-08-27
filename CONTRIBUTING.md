# Contributing to ACS Must-Gather

Thanks for helping improve ACS Must-Gather. This project has two moving parts:

- **`collection-scripts/`** — the bash collectors that run inside the
  must-gather image (entrypoint `gather`, shared helpers in `common.sh`).
- **`analysis/acs-analyze`** — a stdlib-only Python tool that reads an extracted
  bundle *offline* and prints a health report.

Both are covered by `make lint` and `make test`, which CI runs on every pull
request.

## Prerequisites

- `python3` (the analyzer and its tests are stdlib-only — no `pip install`)
- [`shellcheck`](https://www.shellcheck.net/) for linting the collectors
- `podman` (or Docker) only if you build the image

## Development workflow

1. Fork/branch off `main` (e.g. `feat/...`, `fix/...`, `docs/...`, `ci/...`).
2. Make your change.
3. Run the checks locally — they must pass before you open a PR:
   ```sh
   make lint    # shellcheck + analyzer py_compile
   make test    # analyzer unit tests
   ```
   No output from `make lint` means it passed (both tools are silent on
   success). `$?` is `0` on success.
4. Add a `CHANGELOG.md` entry if the change is user-visible (see below).
5. Open a PR against `main`. CI runs `make lint` and `make test`; keep it green.

Useful targets:

```sh
make build                       # build the image (podman, linux/amd64)
make analyze BUNDLE=path/to/mg   # run the analyzer against an extracted bundle
```

## Collection scripts (bash)

The collectors run against a live cluster inside `oc adm must-gather`, so they
follow a few hard conventions:

- **Never use `set -e`.** Collection must continue even when individual commands
  fail — a single missing resource should not abort the run. Make each command
  best-effort (`... || true`) and log what happened.
- **Reuse `common.sh` helpers** rather than re-implementing them: `log_msg`,
  `inspect_resource` / `inspect_namespace`, `resource_exists`, the namespace
  discovery helpers, and `collect_via_pf` for endpoints reached via
  `oc port-forward`.
- **On failure, leave a breadcrumb.** Best-effort collectors write a
  `<file>.error` next to the missing output (the analyzer's "Collection errors"
  check surfaces these) and still exit `0`.
- **Gate new advanced collectors behind a toggle and a timeout** env var, with a
  sensible default (see existing `GATHER_*` toggles and `*_TIMEOUT` variables in
  the README's *Environment Variables* section).
- **Keep it shellcheck-clean.** `.shellcheckrc` sets the source path and the
  handful of globally-disabled rules; prefer a scoped
  `# shellcheck disable=SCxxxx` with a reason over widening the global list.
- Start every script with `#!/bin/bash`.

## Analyzer (`analysis/acs-analyze`)

- **Stdlib only.** The analyzer must run anywhere `python3` exists, with no
  dependencies to install. (`go` is used opportunistically for heap profiles and
  is treated as optional — those checks `SKIP` when it is absent.)
- **Offline.** It reads extracted files only; it never contacts a cluster.
- **Be tolerant of missing/partial data.** A missing input should produce a
  `SKIP` (or stay quiet), not a crash. Use the `OK` / `WARN` / `FAIL` / `SKIP` /
  `INFO` result model already in place.
- Adding a check: write a `check_*` function that appends `Result`s to the
  report, register it in `main()`, and add tests.

## Tests

Unit tests live in `tests/` and use the stdlib `unittest` runner:

```sh
make test
# or: python3 -m unittest discover -s tests -p 'test_*.py' -v
```

New analyzer behavior should come with a test. The suite loads the extension-less
`acs-analyze` script as a module and builds small fixture bundles in a
`tempfile` directory — follow the existing patterns in
`tests/test_analyze.py`.

## Changelog

Add a `CHANGELOG.md` entry when your change is user-visible and *particularly
noteworthy* — especially deprecations or non-obvious side effects. Purely
internal refactors, test-only, and CI/tooling changes usually don't need one.

## Commit messages & PRs

- Keep the subject short and imperative; a type prefix (`ci:`, `docs:`, `fix:`,
  `feat:`) is welcome and matches recent history.
- Explain the *why* in the body when it isn't obvious from the diff.
- Ensure `make lint` and `make test` pass before requesting review.
