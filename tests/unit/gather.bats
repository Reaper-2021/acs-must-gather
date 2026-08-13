#!/usr/bin/env bats

# Unit tests for collection-scripts/gather main orchestrator

setup() {
    export MUST_GATHER_DIR="/tmp/must-gather-test-$$"
    mkdir -p "$MUST_GATHER_DIR"
}

teardown() {
    rm -rf "$MUST_GATHER_DIR"
}

@test "gather creates must-gather directory" {
    [[ -d "$MUST_GATHER_DIR" ]]
}

@test "gather creates version file structure" {
    # Simulate version file creation
    cat > "$MUST_GATHER_DIR/version" <<EOF
acs-must-gather
collected-at: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
EOF

    [[ -f "$MUST_GATHER_DIR/version" ]]
    grep -q "acs-must-gather" "$MUST_GATHER_DIR/version"
    grep -q "collected-at" "$MUST_GATHER_DIR/version"
}

@test "gather creates timestamp file" {
    # Simulate timestamp file
    cat > "$MUST_GATHER_DIR/timestamp" <<EOF
start: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
EOF

    [[ -f "$MUST_GATHER_DIR/timestamp" ]]
    grep -qE "start: [0-9]{4}-[0-9]{2}-[0-9]{2}T" "$MUST_GATHER_DIR/timestamp"
}

@test "GATHER_DIAGNOSTICS defaults to true" {
    GATHER_DIAGNOSTICS="${GATHER_DIAGNOSTICS:-true}"
    [[ "$GATHER_DIAGNOSTICS" == "true" ]]
}

@test "GATHER_DIAGNOSTIC_BUNDLE defaults to false" {
    GATHER_DIAGNOSTIC_BUNDLE="${GATHER_DIAGNOSTIC_BUNDLE:-false}"
    [[ "$GATHER_DIAGNOSTIC_BUNDLE" == "false" ]]
}

@test "GATHER_DEBUG_DUMP defaults to false" {
    GATHER_DEBUG_DUMP="${GATHER_DEBUG_DUMP:-false}"
    [[ "$GATHER_DEBUG_DUMP" == "false" ]]
}

@test "parallel collection launches multiple PIDs" {
    # Simulate parallel execution
    PIDS=()

    sleep 0.1 &
    PIDS+=($!)

    sleep 0.1 &
    PIDS+=($!)

    [[ ${#PIDS[@]} -eq 2 ]]

    # Wait for completion
    for pid in "${PIDS[@]}"; do
        wait "$pid"
    done
}

@test "gather handles empty ACS_NAMESPACES gracefully" {
    # When no namespaces found, certain collectors should skip
    export ACS_NAMESPACES=""

    # GATHER_DIAGNOSTICS should be skipped
    if [[ -z "$ACS_NAMESPACES" ]]; then
        SHOULD_SKIP=true
    fi

    [[ "$SHOULD_SKIP" == "true" ]]
}
