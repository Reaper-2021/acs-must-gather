# Versioning and RHACS alignment

## Image semver

`acs-must-gather` uses [semantic versioning](https://semver.org/) for the image
itself. The current version is written to `/must-gather/version` (line 2) and
defaults to the value of `ACS_MUST_GATHER_VERSION` in
`collection-scripts/common.sh`.

| Release | Version | Notes |
|---|---|---|
| Tier 1 correctness | 1.6.1 | Central API helpers, contract fixes |
| Tier 2 enterprise hardening | 1.7.0 | BATS, REDUCE_LOGS, CI image scan |
| Tier 3 StackRox bar | 1.8.0 | ROX_API_TOKEN, integration tests, gitleaks |
| Vuln-report env scrub | 1.8.1 | Redact container env values in workloads export |

## RHACS minor-version tags

This image is **not** part of the RHACS operator payload. To make support
triage easier, publish (or pull) an additional tag that names the RHACS minor
release you validated against:

```text
quay.io/<org>/acs-must-gather:1.8.0-rhacs4.6
quay.io/<org>/acs-must-gather:rhacs-4.6
```

**Convention:**

- `rhacs-X.Y` — floating tag for the latest `acs-must-gather` build tested on RHACS X.Y.
- `A.B.C-rhacsX.Y` — immutable pin pairing image `A.B.C` with a specific RHACS minor.

When RHACS ships a new minor (for example 4.7), cut a new `acs-must-gather`
release (or at minimum re-tag after smoke-testing collectors against 4.7) and
update the compatibility table in the README.

## Compatibility matrix

Maintain this table when you validate a new RHACS minor:

| RHACS minor | Recommended image tag | Validated `acs-must-gather` |
|---|---|---|
| 4.5 | `rhacs-4.5` | 1.6.x – 1.8.x |
| 4.6 | `rhacs-4.6` | 1.8.0+ |

Collectors target stable Central REST paths (`/v1/*`, `/debug/*`) shared across
recent RHACS releases. Re-test Central API collectors when RHACS deprecates or
renames endpoints.

## Distribution status

`acs-must-gather` is **community / support tooling**. It is **not** published to
`registry.redhat.io` and is **not** a Red Hat supported product component.

For officially supported RHACS diagnostics use:

- `roxctl central debug download-diagnostics`
- `roxctl central debug dump`

This image wraps those APIs plus additional OpenShift-scoped data for support
engineers who need a single `oc adm must-gather` bundle.
