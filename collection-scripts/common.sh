#!/bin/bash

# ACS Must-Gather - Shared Utilities
# Sourced by all collection scripts. Do not execute directly.

MUST_GATHER_DIR="${MUST_GATHER_DIR:-/must-gather}"
INSPECT_TIMEOUT="${INSPECT_TIMEOUT:-120}"
DIAG_TIMEOUT="${DIAG_TIMEOUT:-30}"

log_msg() {
    local msg
    msg="[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"
    echo "${msg}"
    echo "${msg}" >> "${MUST_GATHER_DIR}/gather.log"
}

get_log_collection_args() {
    if [[ -n "${MUST_GATHER_SINCE_TIME:-}" ]]; then
        echo "--since-time=${MUST_GATHER_SINCE_TIME}"
    elif [[ -n "${MUST_GATHER_SINCE:-}" ]]; then
        echo "--since=${MUST_GATHER_SINCE}"
    fi
}

# inspect_resource <resource> [namespace]
# Wrapper around oc adm inspect with timeout, dest-dir, and log-collection args.
inspect_resource() {
    local resource="$1"
    local namespace="${2:-}"

    local ns_arg=""
    if [[ -n "${namespace}" ]]; then
        ns_arg="-n ${namespace}"
    fi

    local log_args
    log_args="$(get_log_collection_args)"

    log_msg "  Inspecting ${resource}${namespace:+ in ${namespace}}"
    # shellcheck disable=SC2086
    timeout "${INSPECT_TIMEOUT}" \
        oc adm inspect ${ns_arg} --dest-dir="${MUST_GATHER_DIR}" \
        ${log_args} "${resource}" 2>&1 || true
}

inspect_namespace() {
    local namespace="$1"
    log_msg "Inspecting namespace ${namespace}"
    inspect_resource "ns/${namespace}"
}

discover_operator_namespace() {
    local ns

    # Strategy 1: find by pod label
    ns=$(oc get pods -A \
        -l 'app.kubernetes.io/name=rhacs-operator' \
        -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null) || true
    if [[ -n "${ns}" ]]; then
        echo "${ns}"
        return
    fi

    # Strategy 2: find by deployment name
    ns=$(oc get deployment -A \
        -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null \
        | grep "rhacs-operator-controller-manager" \
        | awk '{print $1}' | head -1) || true
    if [[ -n "${ns}" ]]; then
        echo "${ns}"
        return
    fi

    # Strategy 3: well-known namespaces
    for candidate in "rhacs-operator" "openshift-operators"; do
        if oc get deployment -n "${candidate}" rhacs-operator-controller-manager &>/dev/null 2>&1; then
            echo "${candidate}"
            return
        fi
    done

    echo ""
}

discover_acs_namespaces() {
    local namespaces=""

    local central_ns
    central_ns=$(oc get Central -A \
        -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}' 2>/dev/null) || true
    if [[ -n "${central_ns}" ]]; then
        namespaces="${central_ns}"
    fi

    local sc_ns
    sc_ns=$(oc get SecuredCluster -A \
        -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}' 2>/dev/null) || true
    if [[ -n "${sc_ns}" ]]; then
        namespaces="${namespaces}"$'\n'"${sc_ns}"
    fi

    echo "${namespaces}" | sort -u | grep -v '^$'
}

discover_acs_crds() {
    oc get crd -o json 2>/dev/null \
        | jq -r '.items[]
            | select(.spec.group | test("stackrox\\.io$"))
            | .metadata.name' 2>/dev/null || true
}

resource_exists() {
    local resource="$1"
    local namespace="${2:-}"
    local ns_arg=""
    if [[ -n "${namespace}" ]]; then
        ns_arg="-n ${namespace}"
    fi
    # shellcheck disable=SC2086
    oc get ${ns_arg} "${resource}" &>/dev/null
}

# ---------- Central access helpers ----------
# Shared by gather_diagnostics, gather_diagnostic_bundle, and gather_debug_dump.

# find_central_pod
# Locates a running Central pod across the namespaces in ACS_NAMESPACES.
# On success sets globals CENTRAL_POD and CENTRAL_NS and returns 0;
# returns 1 if no running Central pod is found.
find_central_pod() {
    CENTRAL_POD=""
    CENTRAL_NS=""
    local ns pod
    while IFS= read -r ns; do
        [[ -z "${ns}" ]] && continue
        pod=$(oc get pods -n "${ns}" -l app=central \
            --field-selector=status.phase=Running \
            -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || true
        if [[ -n "${pod}" ]]; then
            CENTRAL_POD="${pod}"
            CENTRAL_NS="${ns}"
            return 0
        fi
    done <<< "${ACS_NAMESPACES}"
    return 1
}

# get_central_admin_password <namespace>
# Retrieves the Central admin password from known secrets, trying the current
# central-htpasswd secret first and falling back to the legacy
# stackrox-admin-password secret. Prints the password on success (empty if none).
get_central_admin_password() {
    local ns="$1"
    local pw
    pw=$(oc get secret -n "${ns}" central-htpasswd \
        -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null) || true
    if [[ -z "${pw}" ]]; then
        # Log to stderr: this function's stdout is captured by the caller as
        # the password, so the log line must not land there.
        log_msg "WARNING: Could not retrieve admin password from central-htpasswd secret. Trying alternative secret names..." >&2
        pw=$(oc get secret -n "${ns}" stackrox-admin-password \
            -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null) || true
    fi
    printf '%s' "${pw}"
}

# start_central_port_forward <namespace> <pod>
# Finds a free local port (starting at 8443) and starts an oc port-forward to
# Central's 8443 in the background. On success sets globals LOCAL_PORT and
# PF_PID and returns 0; logs the reason and returns 1 on failure.
start_central_port_forward() {
    local ns="$1"
    local pod="$2"
    LOCAL_PORT=8443
    while lsof -Pi :${LOCAL_PORT} -sTCP:LISTEN -t >/dev/null 2>&1; do
        LOCAL_PORT=$((LOCAL_PORT + 1))
        if [[ ${LOCAL_PORT} -gt 9000 ]]; then
            log_msg "ERROR: Could not find available local port for port-forward"
            return 1
        fi
    done
    log_msg "Using local port ${LOCAL_PORT} for port-forward"
    oc port-forward -n "${ns}" "${pod}" "${LOCAL_PORT}:8443" >/dev/null 2>&1 &
    PF_PID=$!
    sleep 3
    if ! kill -0 "${PF_PID}" 2>/dev/null; then
        log_msg "ERROR: Port-forward process died"
        return 1
    fi
    log_msg "Port-forward established (PID: ${PF_PID})"
    return 0
}

# stop_central_port_forward
# Terminates the port-forward started by start_central_port_forward, if any.
stop_central_port_forward() {
    if [[ -n "${PF_PID:-}" ]]; then
        kill "${PF_PID}" 2>/dev/null || true
        wait "${PF_PID}" 2>/dev/null || true
    fi
}

# curl_central_download <url> <output_file> <timeout_secs> <password>
# Authenticated download from Central. The admin password is written to a
# temporary curl config file (mode 600) and passed via --config so it never
# appears on the process command line (visible via ps / /proc). Uses -k
# intentionally: Central serves a self-signed certificate on the localhost
# port-forward, so hostname/CA verification is not applicable. Returns curl's
# exit code (124 indicates a timeout).
curl_central_download() {
    local url="$1"
    local output_file="$2"
    local timeout_secs="$3"
    local password="$4"
    local cfg rc
    cfg="$(mktemp)"
    chmod 600 "${cfg}"
    printf 'user = "admin:%s"\n' "${password}" > "${cfg}"
    timeout "${timeout_secs}" \
        curl -sSk --config "${cfg}" "${url}" -o "${output_file}" 2>/dev/null
    rc=$?
    rm -f "${cfg}"
    return "${rc}"
}
