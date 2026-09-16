# Security Policy

## Supported Versions

Security fixes are applied to the latest release on the `main` branch. Older
tags are not actively supported unless you open an issue explaining the need.

## Reporting a Vulnerability

If you discover a security issue in **acs-must-gather** (the collectors, image,
or analyzer), please report it privately rather than opening a public GitHub
issue:

1. Open a [GitHub Security Advisory](https://github.com/Reaper-2021/acs-must-gather/security/advisories/new) against this repository, **or**
2. Contact the maintainer through GitHub with a private message.

Include steps to reproduce, affected versions, and the impact (e.g. credential
exposure, privilege escalation, data leak).

## Sensitive Data in Must-Gather Output

This image collects **diagnostic** data for RHACS support. Treat every
must-gather bundle as **confidential**:

| Layer | Sensitivity | Notes |
|---|---|---|
| `oc adm inspect` output | Medium | Kubernetes secrets are redacted by default, but configs and logs may still contain cluster-identifying data. |
| `acs-diagnostic-bundle/` | Medium–High | Official RHACS bundle; scrubbed auth providers, but includes cluster topology and logs. |
| `acs-debug-dump/` | High | Central profiling data and database diagnostics. |
| `advanced-acs-diagnostics/tls-certs/` | Medium | **Public certificate material only** — private keys are never decoded. |
| `advanced-acs-diagnostics/vuln-report/` | High | Per-image CVE findings and policy violations across the fleet. |
| `gather.log` | Medium | May reference namespaces, pod names, and endpoint paths. |

**Operational guidance:**

- Transfer bundles only over encrypted channels (SFTP, support-case upload, etc.).
- Do not commit extracted must-gather directories to git or share them in public tickets.
- Disable layers you do not need (`GATHER_ADV_VULN_REPORT=false`, `GATHER_DEBUG_DUMP=false`, etc.) when a smaller bundle is sufficient.

## Credentials Used During Collection

The image reads the Central **admin password** from the `central-htpasswd` or
`stackrox-admin-password` secret to call Central's authenticated API over a
short-lived `oc port-forward`. The password is:

- Never passed on the `curl` command line (mode-600 curl config file instead).
- Not written into the must-gather output.
- Only held in memory for the duration of each API call.

The must-gather pod itself runs with the privileges granted by
`oc adm must-gather` (typically cluster-admin for the temporary service account).
See the README *Permissions* section for details.

## Dependency and Image Scanning

CI builds the container image and runs a [Trivy](https://github.com/aquasecurity/trivy)
scan on every pull request. The base image (`origin-must-gather`) may report
HIGH findings in the bundled `oc` binary; those come from the upstream OpenShift
payload, not from packages installed in this Dockerfile.
