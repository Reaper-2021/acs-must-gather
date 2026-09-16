#!/bin/bash
# Fail when tracked paths look like extracted must-gather output.
# Run in CI and locally before commit.

set -uo pipefail

violations=()
while IFS= read -r path; do
    [[ -z "${path}" ]] && continue
    case "${path}" in
        must-gather.local.*/*|must-gather/*|quay-io-*/*|*/quay-io-*/*)
            violations+=("${path}")
            ;;
    esac
done < <(git ls-files)

if ((${#violations[@]} > 0)); then
    echo "ERROR: must-gather bundle paths must not be committed:" >&2
    printf '  %s\n' "${violations[@]}" >&2
    echo "Extract bundles outside the repo (see .gitignore) or use a temp directory." >&2
    exit 1
fi

echo "No committed must-gather bundle paths detected."
