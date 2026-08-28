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

# ---------- Central authenticated API session ----------
# Five collectors talk to Central the same way: find a Running Central pod,
# read the admin password into a mode-600 curl --config file (never on argv /
# never exported), and port-forward to :8443. Use open_central_session /
# cleanup_central_session instead of copying that sequence.

# discover_running_central
# Sets CENTRAL_NS and CENTRAL_POD from ACS_NAMESPACES. Returns 0 if a Running
# app=central pod was found, 1 otherwise (vars left empty).
discover_running_central() {
    CENTRAL_NS=""
    CENTRAL_POD=""
    local ns pod
    while IFS= read -r ns; do
        [[ -z "${ns}" ]] && continue
        pod=$(oc get pods -n "${ns}" -l app=central \
            --field-selector=status.phase=Running \
            -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || true
        if [[ -n "${pod}" ]]; then
            CENTRAL_NS="${ns}"
            CENTRAL_POD="${pod}"
            return 0
        fi
    done <<< "${ACS_NAMESPACES:-}"
    return 1
}

# write_central_curl_config <namespace>
# Reads central-htpasswd (then stackrox-admin-password), writes a curl --config
# file with a safely escaped `user = "admin:..."` line, and sets CURL_CONFIG to
# its path. The password is a function-local and is unset before return; it is
# never exported. Returns 0 on success, 1 if no password was found.
write_central_curl_config() {
    local ns="$1"
    local password="" escaped=""
    CURL_CONFIG=""

    password=$(oc get secret -n "${ns}" central-htpasswd \
        -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null) || true
    if [[ -z "${password}" ]]; then
        password=$(oc get secret -n "${ns}" stackrox-admin-password \
            -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null) || true
    fi
    if [[ -z "${password}" ]]; then
        unset password
        return 1
    fi

    CURL_CONFIG="$(mktemp)"
    chmod 600 "${CURL_CONFIG}"
    # curl --config double-quoted values treat \, ", and $ as special.
    escaped="${password//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    escaped="${escaped//\$/\\$}"
    printf 'user = "admin:%s"\n' "${escaped}" > "${CURL_CONFIG}"
    unset password escaped
    return 0
}

# start_port_forward <ns> <pod> <remote_port>
# Lets oc pick a free local port (`:<remote_port>`) so concurrent gatherers do
# not race. On success sets PF_PID, LOCAL_PORT, PF_LOG and returns 0. On
# failure cleans up and returns 1 (vars cleared).
start_port_forward() {
    local ns="$1" pod="$2" remote_port="$3"
    local _
    PF_LOG="$(mktemp)"
    oc port-forward -n "${ns}" "${pod}" ":${remote_port}" > "${PF_LOG}" 2>&1 &
    PF_PID=$!
    LOCAL_PORT=""
    for _ in $(seq 1 20); do
        LOCAL_PORT=$(grep -oE 'Forwarding from 127\.0\.0\.1:[0-9]+' "${PF_LOG}" 2>/dev/null \
            | grep -oE '[0-9]+$' | head -1)
        [[ -n "${LOCAL_PORT}" ]] && break
        kill -0 "${PF_PID}" 2>/dev/null || break
        sleep 0.5
    done
    if [[ -z "${LOCAL_PORT}" ]] || ! kill -0 "${PF_PID}" 2>/dev/null; then
        kill "${PF_PID}" 2>/dev/null || true
        wait "${PF_PID}" 2>/dev/null || true
        rm -f "${PF_LOG}"
        PF_PID=""; LOCAL_PORT=""; PF_LOG=""
        return 1
    fi
    return 0
}

# start_central_port_forward
# Port-forwards CENTRAL_POD:8443. Sets PF_PID / LOCAL_PORT / PF_LOG.
start_central_port_forward() {
    if ! start_port_forward "${CENTRAL_NS}" "${CENTRAL_POD}" 8443; then
        return 1
    fi
    log_msg "Port-forward established on local port ${LOCAL_PORT} (PID: ${PF_PID})"
    return 0
}

# cleanup_central_session
# Tears down the tunnel and removes the curl config / port-forward log.
# Safe when the session vars are empty.
cleanup_central_session() {
    if [[ -n "${PF_PID:-}" ]]; then
        kill "${PF_PID}" 2>/dev/null || true
        wait "${PF_PID}" 2>/dev/null || true
    fi
    rm -f "${CURL_CONFIG:-}" "${PF_LOG:-}"
    PF_PID=""; LOCAL_PORT=""; PF_LOG=""; CURL_CONFIG=""
}

# open_central_session <auth_mode> <error_file> [skip_label]
# auth_mode:
#   required - Central pod, admin password, and port-forward are all required
#   optional - pod + port-forward required; password optional (CURL_CONFIG
#              may be empty; auth-required endpoints will fail)
# Writes a reason to <error_file> and returns 1 on failure. On success sets
# CENTRAL_NS, CENTRAL_POD, PF_PID, LOCAL_PORT, PF_LOG, CURL_CONFIG.
open_central_session() {
    local auth_mode="$1"
    local error_file="$2"
    local skip_label="${3:-}"
    local skip_suffix=""
    [[ -n "${skip_label}" ]] && skip_suffix=" Skipping ${skip_label}."

    CENTRAL_NS=""; CENTRAL_POD=""
    PF_PID=""; LOCAL_PORT=""; PF_LOG=""; CURL_CONFIG=""

    if ! discover_running_central; then
        log_msg "WARNING: No running Central pod found.${skip_suffix}"
        [[ -n "${error_file}" ]] && echo "No running Central pod found." > "${error_file}"
        return 1
    fi
    log_msg "Found Central pod: ${CENTRAL_POD} in namespace ${CENTRAL_NS}"

    if ! write_central_curl_config "${CENTRAL_NS}"; then
        if [[ "${auth_mode}" == "required" ]]; then
            log_msg "WARNING: Could not retrieve Central admin password.${skip_suffix}"
            if [[ -n "${error_file}" ]]; then
                echo "Could not retrieve Central admin password (checked central-htpasswd and stackrox-admin-password)." \
                    > "${error_file}"
            fi
            return 1
        fi
        log_msg "WARNING: Could not retrieve Central admin password; auth-required endpoints will fail."
    fi

    if ! start_central_port_forward; then
        log_msg "ERROR: Port-forward to Central failed to establish"
        [[ -n "${error_file}" ]] && echo "Port-forward to Central failed to establish." > "${error_file}"
        rm -f "${CURL_CONFIG:-}"
        CURL_CONFIG=""
        return 1
    fi
    return 0
}

# collect_via_pf <ns> <pod> <remote_port> <path> <outfile> [scheme] [curl_extra...]
# Opens a short-lived port-forward to <pod>:<remote_port>, curls
# <scheme>://127.0.0.1:<port><path> (scheme defaults to http), writes the body to
# <outfile>, and always tears the tunnel down. Best-effort: on any failure it
# writes <outfile>.error and still returns 0. Honors PF_TIMEOUT (falling back to
# DIAG_TIMEOUT, then 30s). Extra args after the scheme are passed to curl (e.g.
# `-k` for a self-signed HTTPS endpoint).
collect_via_pf() {
    local ns="$1" pod="$2" remote_port="$3" path="$4" outfile="$5"
    local scheme="${6:-http}"
    local curl_extra=()
    if [[ "$#" -gt 6 ]]; then
        shift 6
        curl_extra=("$@")
    fi

    # Preserve an in-flight Central session's PF_* globals if this is called
    # from the same process (it currently is not, but keep the helper reentrant).
    local saved_pid="${PF_PID:-}" saved_port="${LOCAL_PORT:-}" saved_log="${PF_LOG:-}"
    if ! start_port_forward "${ns}" "${pod}" "${remote_port}"; then
        PF_PID="${saved_pid}"; LOCAL_PORT="${saved_port}"; PF_LOG="${saved_log}"
        log_msg "  WARNING: port-forward to ${pod}:${remote_port} failed"
        echo "port-forward to ${pod}:${remote_port} failed" > "${outfile}.error"
        return 0
    fi
    local pf_pid="${PF_PID}" local_port="${LOCAL_PORT}" pf_log="${PF_LOG}"
    PF_PID="${saved_pid}"; LOCAL_PORT="${saved_port}"; PF_LOG="${saved_log}"

    if ! timeout "${PF_TIMEOUT:-${DIAG_TIMEOUT:-30}}" \
        curl -sSf "${curl_extra[@]}" "${scheme}://127.0.0.1:${local_port}${path}" \
        -o "${outfile}" 2>/dev/null; then
        log_msg "  WARNING: fetch failed: ${pod}:${remote_port}${path}"
        echo "fetch failed: ${pod}:${remote_port}${path}" > "${outfile}.error"
        rm -f "${outfile}" 2>/dev/null || true
    fi

    kill "${pf_pid}" 2>/dev/null || true
    wait "${pf_pid}" 2>/dev/null || true
    rm -f "${pf_log}"
}
