# Shared helpers for BATS tests.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="${PROJECT_ROOT}/collection-scripts"
MOCKS_DIR="${BATS_TEST_DIRNAME}/mocks"

setup() {
    TEST_TMPDIR="${BATS_TEST_TMPDIR}"
    mkdir -p "${TEST_TMPDIR}/mocks"
    export PATH="${TEST_TMPDIR}/mocks:${MOCKS_DIR}:${PATH}"
    export MUST_GATHER_DIR="${TEST_TMPDIR}/must-gather"
    mkdir -p "${MUST_GATHER_DIR}"
}

# create_mock_oc <central_pod> [admin_password]
# Writes a per-test oc stub into TEST_TMPDIR/mocks that shadows the repo mock.
create_mock_oc() {
    local central_pod="${1:-}"
    local admin_password="${2:-}"
    cat > "${TEST_TMPDIR}/mocks/oc" <<EOF
#!/usr/bin/env bash
[[ -n "\${MOCK_OC_LOG_FILE:-}" ]] && printf '%s\n' "\$*" >> "\${MOCK_OC_LOG_FILE}"
if [[ "\$1" == "get" && "\$2" == "pods" && "\$*" == *"app=central"* ]]; then
    echo "${central_pod}"
    exit 0
fi
if [[ "\$1" == "get" && "\$2" == "secret" && "\$*" == *"central-htpasswd"* ]]; then
    if [[ -n "${admin_password}" ]]; then
        printf '%s' "${admin_password}" | base64
    fi
    exit 0
fi
if [[ "\$1" == "port-forward" ]]; then
    echo "Forwarding from 127.0.0.1:18443 -> 8443"
    # Stay alive so start_central_port_forward can detect the local port.
    exec tail -f /dev/null
    exit 0
fi
if [[ "\$1" == "adm" && "\$2" == "inspect" ]]; then
    exit 0
fi
exit 0
EOF
    chmod +x "${TEST_TMPDIR}/mocks/oc"
}
