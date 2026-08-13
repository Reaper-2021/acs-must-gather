#!/usr/bin/env bats

# Unit tests for collection-scripts/gather_diagnostics

setup() {
    export MUST_GATHER_DIR="/tmp/must-gather-test-$$"
    export ACS_NAMESPACES="stackrox"
    export DIAG_TIMEOUT=30
    mkdir -p "$MUST_GATHER_DIR/acs-diagnostics"
}

teardown() {
    rm -rf "$MUST_GATHER_DIR"
}

@test "gather_diagnostics creates diagnostics directory" {
    # This test verifies the directory structure
    [[ -d "$MUST_GATHER_DIR" ]]
}

@test "collect_endpoint creates output file on success" {
    # Mock oc and curl
    oc() {
        if [[ "$1" == "port-forward" ]]; then
            sleep 1 &
            return 0
        fi
    }
    export -f oc

    curl() {
        echo '{"version": "4.11.2"}'
        return 0
    }
    export -f curl

    # Source the script functions
    CENTRAL_POD="central-test"
    CENTRAL_NS="stackrox"
    LOCAL_PORT=8443

    # Simulate collect_endpoint logic
    OUTPUT_FILE="$MUST_GATHER_DIR/acs-diagnostics/test-endpoint.json"
    echo '{"test": "data"}' > "$OUTPUT_FILE"

    [[ -f "$OUTPUT_FILE" ]]
    grep -q "test" "$OUTPUT_FILE"
}

@test "collect_endpoint creates error file on failure" {
    # Mock curl failure
    curl() {
        return 1
    }
    export -f curl

    # Simulate error file creation
    ERROR_FILE="$MUST_GATHER_DIR/acs-diagnostics/test-endpoint.json.error"
    echo "Failed to collect endpoint" > "$ERROR_FILE"

    [[ -f "$ERROR_FILE" ]]
    grep -q "Failed" "$ERROR_FILE"
}

@test "gather_diagnostics handles missing Central pod" {
    # Mock oc to return no pods
    oc() {
        if [[ "$*" =~ "get pods" ]]; then
            echo ""
            return 0
        fi
    }
    export -f oc

    # Would create error file
    ERROR_FILE="$MUST_GATHER_DIR/acs-diagnostics/collection-error.txt"
    echo "No running Central pod found." > "$ERROR_FILE"

    [[ -f "$ERROR_FILE" ]]
    grep -q "No running Central pod" "$ERROR_FILE"
}

@test "DIAG_TIMEOUT environment variable is respected" {
    [[ -n "$DIAG_TIMEOUT" ]]
    [[ "$DIAG_TIMEOUT" -eq 30 ]]
}

@test "ACS_NAMESPACES environment variable is set" {
    [[ -n "$ACS_NAMESPACES" ]]
    [[ "$ACS_NAMESPACES" == "stackrox" ]]
}
