#!/usr/bin/env bats
# Integration tests with recorded Central API fixtures and mocked oc/curl.

load test_helper

setup_collector_path() {
    local collector="$1"
    mkdir -p "${TEST_TMPDIR}/usr/bin"
    cp "${SCRIPT_DIR}/common.sh" "${TEST_TMPDIR}/usr/bin/"
    sed "s|/usr/bin/common.sh|${TEST_TMPDIR}/usr/bin/common.sh|g" \
        "${SCRIPT_DIR}/${collector}" > "${TEST_TMPDIR}/usr/bin/${collector}"
    chmod +x "${TEST_TMPDIR}/usr/bin/${collector}"
}

setup_gather_path() {
    mkdir -p "${TEST_TMPDIR}/usr/bin"
    cp "${SCRIPT_DIR}/common.sh" "${TEST_TMPDIR}/usr/bin/"
    for stub in gather_cluster_scoped gather_operator gather_central gather_secured_cluster \
        gather_diagnostics gather_diagnostic_bundle gather_debug_dump gather_advanced; do
        printf '#!/bin/bash\nexit 0\n' > "${TEST_TMPDIR}/usr/bin/${stub}"
        chmod +x "${TEST_TMPDIR}/usr/bin/${stub}"
    done
    sed -e "s|/usr/bin/common.sh|${TEST_TMPDIR}/usr/bin/common.sh|g" \
        -e "s|/usr/bin/gather_|${TEST_TMPDIR}/usr/bin/gather_|g" \
        "${SCRIPT_DIR}/gather" > "${TEST_TMPDIR}/usr/bin/gather"
    chmod +x "${TEST_TMPDIR}/usr/bin/gather"
}

@test "gather_diagnostics writes fixture-backed Central API snapshots" {
    create_mock_oc "central-abc" "s3cret"
    chmod +x "${MOCKS_DIR}/curl"
    setup_collector_path "gather_diagnostics"
    run bash -c "
        export PATH='${TEST_TMPDIR}/usr/bin:${TEST_TMPDIR}/mocks:${MOCKS_DIR}:${PATH}'
        export ACS_NAMESPACES='stackrox'
        export MUST_GATHER_DIR='${MUST_GATHER_DIR}'
        export MOCK_CURL_FIXTURES_DIR='${BATS_TEST_DIRNAME}/fixtures/central-api'
        export DIAG_TIMEOUT='10'
        gather_diagnostics
        ls -1 \"\${MUST_GATHER_DIR}/acs-diagnostics\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"central-metadata.json"* ]]
    [[ "$output" == *"central-clusters.json"* ]]
    [[ "$output" == *"central-db-status.json"* ]]
    run grep -q '4.6.0' "${MUST_GATHER_DIR}/acs-diagnostics/central-metadata.json"
    [ "$status" -eq 0 ]
}

@test "gather_diagnostics authenticates with ROX_API_TOKEN" {
    create_mock_oc "central-abc" ""
    chmod +x "${MOCKS_DIR}/curl"
    setup_collector_path "gather_diagnostics"
    run bash -c "
        export PATH='${TEST_TMPDIR}/usr/bin:${TEST_TMPDIR}/mocks:${MOCKS_DIR}:${PATH}'
        export ACS_NAMESPACES='stackrox'
        export MUST_GATHER_DIR='${MUST_GATHER_DIR}'
        export ROX_API_TOKEN='test-token-abc'
        export MOCK_CURL_FIXTURES_DIR='${BATS_TEST_DIRNAME}/fixtures/central-api'
        export DIAG_TIMEOUT='10'
        source '${TEST_TMPDIR}/usr/bin/common.sh'
        resolve_central_api_auth
        write_central_curl_config
        grep -q 'Bearer test-token-abc' \"\${CENTRAL_CURL_CONFIG}\"
        gather_diagnostics
        test -s \"\${MUST_GATHER_DIR}/acs-diagnostics/central-metadata.json\"
    "
    [ "$status" -eq 0 ]
}

@test "gather writes OpenShift must-gather version contract" {
    create_mock_oc
    setup_gather_path
    run bash -c "
        export PATH='${TEST_TMPDIR}/usr/bin:${TEST_TMPDIR}/mocks:${MOCKS_DIR}:${PATH}'
        export MUST_GATHER_DIR='${MUST_GATHER_DIR}'
        export GATHER_DIAGNOSTICS='false'
        export GATHER_DIAGNOSTIC_BUNDLE='false'
        export GATHER_DEBUG_DUMP='false'
        export GATHER_ADVANCED='false'
        export ACS_NAMESPACES=''
        gather
        head -2 \"\${MUST_GATHER_DIR}/version\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"acs-must-gather"* ]]
    [[ "$output" == *"1.8.1"* ]]
}
