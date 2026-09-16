#!/usr/bin/env bats
# Tests for collection-scripts/common.sh

load test_helper

@test "get_log_collection_args sets --since from MUST_GATHER_SINCE" {
    run bash -c "
        export MUST_GATHER_SINCE='8h'
        unset MUST_GATHER_SINCE_TIME REDUCE_LOGS
        source '${SCRIPT_DIR}/common.sh'
        get_log_collection_args
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"--since=8h"* ]]
}

@test "get_log_collection_args sets --since-time from MUST_GATHER_SINCE_TIME" {
    run bash -c "
        export MUST_GATHER_SINCE_TIME='2024-01-15T10:00:00Z'
        unset MUST_GATHER_SINCE REDUCE_LOGS
        source '${SCRIPT_DIR}/common.sh'
        get_log_collection_args
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"--since-time=2024-01-15T10:00:00Z"* ]]
}

@test "MUST_GATHER_SINCE_TIME overrides MUST_GATHER_SINCE" {
    run bash -c "
        export MUST_GATHER_SINCE='8h'
        export MUST_GATHER_SINCE_TIME='2024-01-15T10:00:00Z'
        unset REDUCE_LOGS
        source '${SCRIPT_DIR}/common.sh'
        get_log_collection_args
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"--since-time=2024-01-15T10:00:00Z"* ]]
    [[ "$output" != *"--since=8h"* ]]
}

@test "init_log_collection enables rotated pod logs by default" {
    run bash -c "
        unset REDUCE_LOGS
        source '${SCRIPT_DIR}/common.sh'
        init_log_collection
        echo \"rotated=\${ROTATED_POD_LOGS_ARG}\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"rotated=--rotated-pod-logs"* ]]
}

@test "REDUCE_LOGS=skip_rotated_logs omits rotated pod logs arg" {
    run bash -c "
        export REDUCE_LOGS='skip_rotated_logs'
        source '${SCRIPT_DIR}/common.sh'
        init_log_collection
        echo \"rotated=\${ROTATED_POD_LOGS_ARG}\"
        echo \"compress=\${COMPRESS_AFTER_GATHER}\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"rotated="* ]]
    [[ "$output" != *"rotated=--rotated-pod-logs"* ]]
    [[ "$output" == *"compress="* ]]
}

@test "REDUCE_LOGS=compress_logs sets COMPRESS_AFTER_GATHER" {
    run bash -c "
        export REDUCE_LOGS='compress_logs'
        source '${SCRIPT_DIR}/common.sh'
        init_log_collection
        echo \"compress=\${COMPRESS_AFTER_GATHER}\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"compress=true"* ]]
}

@test "REDUCE_LOGS rejects unknown tokens" {
    run bash -c "
        export REDUCE_LOGS='invalid'
        source '${SCRIPT_DIR}/common.sh'
        init_log_collection
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"invalid"* ]]
}

@test "compress_logs gzips large log files" {
    run bash -c "
        source '${SCRIPT_DIR}/common.sh'
        export MUST_GATHER_DIR='${TEST_TMPDIR}/logs'
        mkdir -p \"\${MUST_GATHER_DIR}\"
        dd if=/dev/zero of=\"\${MUST_GATHER_DIR}/large.log\" bs=1024 count=11264 status=none
        echo 'small' > \"\${MUST_GATHER_DIR}/small.log\"
        compress_logs \"\${MUST_GATHER_DIR}\"
        [[ -f \"\${MUST_GATHER_DIR}/large.log.gz\" ]] && echo 'large compressed'
        [[ ! -f \"\${MUST_GATHER_DIR}/large.log\" ]] && echo 'large removed'
        [[ -f \"\${MUST_GATHER_DIR}/small.log\" ]] && echo 'small kept'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"large compressed"* ]]
    [[ "$output" == *"small kept"* ]]
}

@test "discover_central_pod finds a running Central pod" {
    create_mock_oc "central-abc" "admin-pass"
    run bash -c "
        export ACS_NAMESPACES='stackrox'
        source '${SCRIPT_DIR}/common.sh'
        if discover_central_pod; then
            echo \"pod=\${CENTRAL_POD} ns=\${CENTRAL_NS}\"
        fi
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"pod=central-abc"* ]]
    [[ "$output" == *"ns=stackrox"* ]]
}

@test "resolve_central_api_auth prefers ROX_API_TOKEN over admin password" {
    create_mock_oc "central-abc" "s3cret"
    run bash -c "
        export ROX_API_TOKEN='bearer-token'
        export CENTRAL_NS='stackrox'
        source '${SCRIPT_DIR}/common.sh'
        if resolve_central_api_auth; then
            echo \"token=\${CENTRAL_API_TOKEN}\"
            echo \"pw=\${CENTRAL_ADMIN_PASSWORD}\"
        fi
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"token=bearer-token"* ]]
    [[ "$output" != *"pw=s3cret"* ]]
}

@test "write_central_curl_config writes Bearer header for API token" {
    run bash -c "
        source '${SCRIPT_DIR}/common.sh'
        CENTRAL_API_TOKEN='tok123'
        write_central_curl_config
        grep -q 'Bearer tok123' \"\${CENTRAL_CURL_CONFIG}\"
    "
    [ "$status" -eq 0 ]
}

@test "fetch_central_admin_password reads central-htpasswd" {
    create_mock_oc "central-abc" "s3cret"
    run bash -c "
        export CENTRAL_NS='stackrox'
        source '${SCRIPT_DIR}/common.sh'
        if fetch_central_admin_password; then
            echo \"pw=\${CENTRAL_ADMIN_PASSWORD}\"
        fi
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"pw=s3cret"* ]]
}

@test "inspect_resource forwards --all-namespaces to oc adm inspect" {
    create_mock_oc
    export MOCK_OC_LOG_FILE="${TEST_TMPDIR}/oc.log"
    : > "${MOCK_OC_LOG_FILE}"
    run bash -c "
        export MOCK_OC_LOG_FILE='${MOCK_OC_LOG_FILE}'
        export MUST_GATHER_DIR='${MUST_GATHER_DIR}'
        unset REDUCE_LOGS
        source '${SCRIPT_DIR}/common.sh'
        init_log_collection
        inspect_resource 'Central' '' '--all-namespaces'
        cat \"\${MOCK_OC_LOG_FILE}\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"--all-namespaces"* ]]
    [[ "$output" == *"Central"* ]]
}
