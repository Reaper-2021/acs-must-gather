#!/usr/bin/env bats
# Tests for collection-scripts/scrub_vuln_workloads_env

load test_helper

SCRUB="${PROJECT_ROOT}/collection-scripts/scrub_vuln_workloads_env"

@test "scrub_vuln_workloads_env redacts NDJSON env values and keeps keys" {
    local fixture="${TEST_TMPDIR}/workloads.json"
    python3 - <<'PY' > "${fixture}"
import json
rows = [
    {
        "result": {
            "deployment": {
                "name": "image-registry",
                "namespace": "openshift-image-registry",
                "containers": [{
                    "name": "registry",
                    "config": {
                        "env": [
                            {"key": "REGISTRY_HTTP_SECRET", "value": "super-secret-value", "envVarSource": "RAW"},
                            {"key": "RELEASE_VERSION", "value": "4.16.0", "envVarSource": "RAW"},
                            {"key": "EMPTY", "value": "", "envVarSource": "RAW"},
                        ]
                    },
                }],
            },
            "images": [{
                "name": {"fullName": "registry.example/img:1"},
                "scan": {"components": []},
            }],
        }
    },
    {
        "result": {
            "deployment": {
                "name": "other",
                "namespace": "ns",
                "containers": [{
                    "name": "c",
                    "config": {
                        "env": [
                            {"key": "TOKEN", "value": "abc123", "envVarSource": "RAW"},
                        ]
                    },
                }],
            },
            "images": [],
        }
    },
]
for row in rows:
    print(json.dumps(row, separators=(",", ":")))
PY
    run "${SCRUB}" "${fixture}"
    [ "$status" -eq 0 ]

    run jq -r -s '
      .[0].result.deployment.containers[0].config.env[]
      | select(.key=="REGISTRY_HTTP_SECRET") | .value
    ' "${fixture}"
    [ "$status" -eq 0 ]
    [ "$output" = "<redacted>" ]

    run jq -r -s '
      .[0].result.deployment.containers[0].config.env[]
      | select(.key=="REGISTRY_HTTP_SECRET") | .key
    ' "${fixture}"
    [ "$output" = "REGISTRY_HTTP_SECRET" ]

    run jq -r -s '
      .[0].result.deployment.containers[0].config.env[]
      | select(.key=="RELEASE_VERSION") | .value
    ' "${fixture}"
    [ "$output" = "<redacted>" ]

    run jq -r -s '
      .[0].result.deployment.containers[0].config.env[]
      | select(.key=="EMPTY") | .value
    ' "${fixture}"
    [ "$output" = "" ]

    run jq -r -s '
      .[1].result.deployment.containers[0].config.env[0].value
    ' "${fixture}"
    [ "$output" = "<redacted>" ]

    # CVE/image structure preserved for the analyzer
    run jq -r -s '.[0].result.images[0].name.fullName' "${fixture}"
    [ "$output" = "registry.example/img:1" ]

    # No cleartext secret remnant
    run grep -F "super-secret-value" "${fixture}"
    [ "$status" -ne 0 ]
}

@test "scrub_vuln_workloads_env handles single JSON object" {
    local fixture="${TEST_TMPDIR}/one.json"
    cat > "${fixture}" <<'EOF'
{"result":{"deployment":{"containers":[{"config":{"env":[{"key":"P","value":"secret"}]}}]}}}
EOF
    run "${SCRUB}" "${fixture}"
    [ "$status" -eq 0 ]
    run jq -r '.result.deployment.containers[0].config.env[0].value' "${fixture}"
    [ "$output" = "<redacted>" ]
}

@test "scrub_vuln_workloads_env is a no-op on empty file" {
    local fixture="${TEST_TMPDIR}/empty.json"
    : > "${fixture}"
    run "${SCRUB}" "${fixture}"
    [ "$status" -eq 0 ]
    [ ! -s "${fixture}" ]
}

@test "scrub_vuln_workloads_env fails on missing file" {
    run "${SCRUB}" "${TEST_TMPDIR}/missing.json"
    [ "$status" -ne 0 ]
}
