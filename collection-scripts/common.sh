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
