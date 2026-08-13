#!/bin/bash

# Validate must-gather output structure and content

set -euo pipefail

MUST_GATHER_DIR="${1:-/tmp/must-gather-output}"

echo "==> Validating must-gather output structure"

# Check required top-level files
required_files=(
  "version"
  "timestamp"
  "gather.log"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "${MUST_GATHER_DIR}/${file}" ]]; then
    echo "ERROR: Missing required file: ${file}"
    exit 1
  fi
  echo "✓ Found: ${file}"
done

# Check required directories
required_dirs=(
  "cluster-scoped-resources"
  "namespaces"
  "acs-diagnostics"
)

for dir in "${required_dirs[@]}"; do
  if [[ ! -d "${MUST_GATHER_DIR}/${dir}" ]]; then
    echo "ERROR: Missing required directory: ${dir}"
    exit 1
  fi
  echo "✓ Found: ${dir}/"
done

# Validate timestamp format
echo "==> Validating timestamp file"
if ! grep -qE "start: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z" "${MUST_GATHER_DIR}/timestamp"; then
  echo "ERROR: Invalid timestamp format in timestamp file"
  exit 1
fi
echo "✓ Timestamp format valid"

# Validate gather.log exists and has content
echo "==> Validating gather.log"
if [[ ! -s "${MUST_GATHER_DIR}/gather.log" ]]; then
  echo "ERROR: gather.log is empty or missing"
  exit 1
fi

if ! grep -q "gathering" "${MUST_GATHER_DIR}/gather.log"; then
  echo "ERROR: gather.log doesn't contain expected content"
  exit 1
fi
echo "✓ gather.log contains expected content"

# Check for Central diagnostics
echo "==> Validating Central diagnostics"
expected_diag_files=(
  "central-metadata.json"
  "central-clusters.json"
  "central-db-status.json"
  "central-goroutine-dump.txt"
  "central-heap-profile.pb.gz"
)

for file in "${expected_diag_files[@]}"; do
  filepath="${MUST_GATHER_DIR}/acs-diagnostics/${file}"
  if [[ -f "${filepath}" ]]; then
    echo "✓ Found: acs-diagnostics/${file}"
  elif [[ -f "${filepath}.error" ]]; then
    echo "⚠ Found error file: acs-diagnostics/${file}.error (collection failed, but gracefully)"
  else
    echo "⚠ Missing: acs-diagnostics/${file} (may indicate Central not running)"
  fi
done

# Validate namespace resources were collected
echo "==> Validating namespace resources"
if [[ -d "${MUST_GATHER_DIR}/namespaces" ]]; then
  namespace_count=$(find "${MUST_GATHER_DIR}/namespaces" -maxdepth 1 -type d | wc -l)
  if [[ $namespace_count -gt 1 ]]; then
    echo "✓ Found $(($namespace_count - 1)) namespace(s) collected"
  else
    echo "⚠ No namespaces collected (may be expected if no ACS installation found)"
  fi
else
  echo "ERROR: namespaces directory missing"
  exit 1
fi

# Validate cluster-scoped resources
echo "==> Validating cluster-scoped resources"
if [[ -d "${MUST_GATHER_DIR}/cluster-scoped-resources" ]]; then
  if [[ -f "${MUST_GATHER_DIR}/cluster-scoped-resources/core/nodes-summary.txt" ]]; then
    echo "✓ Found nodes summary"
  else
    echo "⚠ Missing nodes summary"
  fi
else
  echo "ERROR: cluster-scoped-resources directory missing"
  exit 1
fi

echo ""
echo "==> Validation completed successfully"
echo "Must-gather output structure is valid"
