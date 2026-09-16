#!/bin/bash

# ACS Must-Gather - Shared Utilities
# Sourced by all collection scripts. Do not execute directly.

MUST_GATHER_DIR="${MUST_GATHER_DIR:-/must-gather}"
INSPECT_TIMEOUT="${INSPECT_TIMEOUT:-120}"
DIAG_TIMEOUT="${DIAG_TIMEOUT:-30}"
# OpenShift must-gather contract: line 2 of /must-gather/version is major.minor.micro.
ACS_MUST_GATHER_VERSION="${ACS_MUST_GATHER_VERSION:-1.6.1}"

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

# inspect_resource <resource> [namespace] [extra oc adm inspect flags...]
# Wrapper around oc adm inspect with timeout, dest-dir, and log-collection args.
# Extra flags after namespace are forwarded (e.g. --all-namespaces). Namespace
# may be empty when the extra flags are the only optional arguments.
inspect_resource() {
    local resource="$1"
    local namespace="${2:-}"
    shift
    if (($# > 0)); then
        shift
    fi

    local ns_flags=()
    if [[ -n "${namespace}" ]]; then
        ns_flags=(-n "${namespace}")
    fi

    local log_args
    log_args="$(get_log_collection_args)"

    local extra_note=""
    if [[ " $* " == *" --all-namespaces "* ]]; then
        extra_note=" (all namespaces)"
    fi
    log_msg "  Inspecting ${resource}${namespace:+ in ${namespace}}${extra_note}"
    # shellcheck disable=SC2086
    timeout "${INSPECT_TIMEOUT}" \
        oc adm inspect "${ns_flags[@]}" --dest-dir="${MUST_GATHER_DIR}" \
        ${log_args} "$@" "${resource}" 2>&1 || true
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

    local pf_log local_port pf_pid _
    pf_log="$(mktemp)"
    oc port-forward -n "${ns}" "${pod}" ":${remote_port}" > "${pf_log}" 2>&1 &
    pf_pid=$!

    local_port=""
    for _ in $(seq 1 20); do
        local_port=$(grep -oE 'Forwarding from 127\.0\.0\.1:[0-9]+' "${pf_log}" 2>/dev/null \
            | grep -oE '[0-9]+$' | head -1)
        [[ -n "${local_port}" ]] && break
        kill -0 "${pf_pid}" 2>/dev/null || break
        sleep 0.5
    done

    if [[ -z "${local_port}" ]] || ! kill -0 "${pf_pid}" 2>/dev/null; then
        log_msg "  WARNING: port-forward to ${pod}:${remote_port} failed"
        echo "port-forward to ${pod}:${remote_port} failed" > "${outfile}.error"
        kill "${pf_pid}" 2>/dev/null || true
        wait "${pf_pid}" 2>/dev/null || true
        rm -f "${pf_log}"
        return 0
    fi

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

# ---------- Central API access (port-forward + admin basic-auth) ----------
# Collectors that query Central's HTTPS API share this flow. Globals are set
# for the lifetime of a session; call cleanup_central_api_session on EXIT.

# discover_central_pod
# Requires ACS_NAMESPACES. Sets CENTRAL_POD and CENTRAL_NS on success.
discover_central_pod() {
    CENTRAL_POD=""
    CENTRAL_NS=""
    while IFS= read -r ns; do
        [[ -z "${ns}" ]] && continue
        local pod
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

# fetch_central_admin_password
# Requires CENTRAL_NS. Sets CENTRAL_ADMIN_PASSWORD; returns 0 when non-empty.
fetch_central_admin_password() {
    CENTRAL_ADMIN_PASSWORD=$(oc get secret -n "${CENTRAL_NS}" central-htpasswd \
        -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null) || true
    if [[ -z "${CENTRAL_ADMIN_PASSWORD}" ]]; then
        CENTRAL_ADMIN_PASSWORD=$(oc get secret -n "${CENTRAL_NS}" stackrox-admin-password \
            -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null) || true
    fi
    [[ -n "${CENTRAL_ADMIN_PASSWORD}" ]]
}

# start_central_port_forward
# Requires CENTRAL_POD and CENTRAL_NS. Sets CENTRAL_LOCAL_PORT, CENTRAL_PF_PID,
# and CENTRAL_PF_LOG. Lets oc pick a free local port so parallel gatherers do
# not collide.
start_central_port_forward() {
    CENTRAL_PF_LOG="$(mktemp)"
    oc port-forward -n "${CENTRAL_NS}" "${CENTRAL_POD}" ":8443" > "${CENTRAL_PF_LOG}" 2>&1 &
    CENTRAL_PF_PID=$!
    CENTRAL_LOCAL_PORT=""
    local _
    for _ in $(seq 1 20); do
        CENTRAL_LOCAL_PORT=$(grep -oE 'Forwarding from 127\.0\.0\.1:[0-9]+' "${CENTRAL_PF_LOG}" 2>/dev/null \
            | grep -oE '[0-9]+$' | head -1)
        [[ -n "${CENTRAL_LOCAL_PORT}" ]] && break
        kill -0 "${CENTRAL_PF_PID}" 2>/dev/null || break
        sleep 0.5
    done
    [[ -n "${CENTRAL_LOCAL_PORT}" ]] && kill -0 "${CENTRAL_PF_PID}" 2>/dev/null
}

stop_central_port_forward() {
    if [[ -n "${CENTRAL_PF_PID:-}" ]]; then
        kill "${CENTRAL_PF_PID}" 2>/dev/null || true
        wait "${CENTRAL_PF_PID}" 2>/dev/null || true
    fi
    CENTRAL_PF_PID=""
    rm -f "${CENTRAL_PF_LOG:-}"
    CENTRAL_PF_LOG=""
    CENTRAL_LOCAL_PORT=""
}

# write_central_curl_config
# Keeps the admin password off the curl command line (visible via ps / /proc).
write_central_curl_config() {
    cleanup_central_curl_config
    [[ -z "${CENTRAL_ADMIN_PASSWORD:-}" ]] && return 0
    CENTRAL_CURL_CONFIG="$(mktemp)"
    chmod 600 "${CENTRAL_CURL_CONFIG}"
    printf 'user = "admin:%s"\n' "${CENTRAL_ADMIN_PASSWORD}" > "${CENTRAL_CURL_CONFIG}"
}

cleanup_central_curl_config() {
    rm -f "${CENTRAL_CURL_CONFIG:-}"
    CENTRAL_CURL_CONFIG=""
}

cleanup_central_api_session() {
    stop_central_port_forward
    cleanup_central_curl_config
}

# central_curl_auth_args
# Echo curl --config args when admin auth is configured (for "$(central_curl_auth_args)").
central_curl_auth_args() {
    if [[ -n "${CENTRAL_CURL_CONFIG:-}" ]]; then
        echo --config "${CENTRAL_CURL_CONFIG}"
    fi
}
