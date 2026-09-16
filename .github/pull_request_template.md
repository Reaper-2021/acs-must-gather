## Summary

<!-- What changed and why? Link related issues if any. -->

## Type of change

- [ ] Bug fix
- [ ] New feature / collector
- [ ] Documentation
- [ ] CI / tooling
- [ ] Refactor

## Test plan

- [ ] `make lint`
- [ ] `make test`
- [ ] `make test-shell` (if collection-scripts changed)
- [ ] `make test-integration` (if collectors or API fixtures changed)
- [ ] `make check-bundles` (no extracted must-gather directories committed)
- [ ] Manual `oc adm must-gather` run (if behaviour changed)

## Checklist

- [ ] User-visible changes have a `CHANGELOG.md` entry
- [ ] New env vars / toggles are documented in `README.md`
- [ ] No secrets, sample must-gather bundles, or credentials committed
