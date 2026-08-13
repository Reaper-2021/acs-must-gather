#!/usr/bin/env bats

# Unit tests for collection-scripts/common.sh

setup() {
    # Source the common functions
    export MUST_GATHER_DIR="/tmp/must-gather-test-$$"
    mkdir -p "$MUST_GATHER_DIR"

    # Source common.sh
    source "${BATS_TEST_DIRNAME}/../../collection-scripts/common.sh"
}

teardown() {
    rm -rf "$MUST_GATHER_DIR"
}

@test "log_msg creates log file" {
    log_msg "Test message"

    [[ -f "${MUST_GATHER_DIR}/gather.log" ]]
    grep -q "Test message" "${MUST_GATHER_DIR}/gather.log"
}

@test "log_msg includes timestamp" {
    log_msg "Timestamped message"

    grep -qE '\[[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\]' "${MUST_GATHER_DIR}/gather.log"
}

@test "get_log_collection_args with MUST_GATHER_SINCE" {
    export MUST_GATHER_SINCE="8h"

    result=$(get_log_collection_args)

    [[ "$result" == "--since=8h" ]]
}

@test "get_log_collection_args with MUST_GATHER_SINCE_TIME" {
    export MUST_GATHER_SINCE_TIME="2024-01-15T10:00:00Z"

    result=$(get_log_collection_args)

    [[ "$result" == "--since-time=2024-01-15T10:00:00Z" ]]
}

@test "get_log_collection_args with both sets SINCE_TIME as priority" {
    export MUST_GATHER_SINCE="8h"
    export MUST_GATHER_SINCE_TIME="2024-01-15T10:00:00Z"

    result=$(get_log_collection_args)

    [[ "$result" == "--since-time=2024-01-15T10:00:00Z" ]]
}

@test "get_log_collection_args with neither returns empty" {
    unset MUST_GATHER_SINCE
    unset MUST_GATHER_SINCE_TIME

    result=$(get_log_collection_args)

    [[ -z "$result" ]]
}

@test "resource_exists returns 0 for existing resource" {
    # Mock oc get to return success
    oc() {
        if [[ "$1" == "get" && "$2" == "pods" ]]; then
            return 0
        fi
    }
    export -f oc

    run resource_exists "pods" "default"

    [[ "$status" -eq 0 ]]
}

@test "resource_exists returns 1 for non-existing resource" {
    # Mock oc get to return failure
    oc() {
        return 1
    }
    export -f oc

    # resource_exists should return 1 when oc fails
    run resource_exists "nonexistent" "default"

    [[ "$status" -eq 1 ]]
}

@test "discover_acs_crds finds stackrox.io CRDs" {
    # Mock oc get crd
    oc() {
        if [[ "$*" == "get crd -o json" ]]; then
            cat <<EOF
{
  "items": [
    {
      "spec": {"group": "platform.stackrox.io"},
      "metadata": {"name": "centrals.platform.stackrox.io"}
    },
    {
      "spec": {"group": "other.example.com"},
      "metadata": {"name": "other.crd"}
    }
  ]
}
EOF
            return 0
        fi
    }
    export -f oc

    result=$(discover_acs_crds)

    echo "$result" | grep -q "centrals.platform.stackrox.io"
    ! echo "$result" | grep -q "other.crd"
}

@test "discover_operator_namespace finds by pod label" {
    # Mock oc to return namespace directly (jsonpath already extracts it)
    oc() {
        if [[ "$*" =~ "get pods -A" && "$*" =~ "rhacs-operator" ]]; then
            echo "rhacs-operator"
            return 0
        fi
        return 1
    }
    export -f oc

    result=$(discover_operator_namespace)

    [[ "$result" == "rhacs-operator" ]]
}

@test "discover_acs_namespaces finds Central namespace" {
    # Mock oc to return namespace directly (jsonpath already extracts it)
    oc() {
        if [[ "$*" =~ "get Central -A" ]]; then
            echo "stackrox"
            return 0
        elif [[ "$*" =~ "get SecuredCluster -A" ]]; then
            echo ""
            return 0
        fi
        return 1
    }
    export -f oc

    result=$(discover_acs_namespaces)

    [[ "$result" == "stackrox" ]]
}
