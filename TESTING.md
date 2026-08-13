# Testing Guide

This document describes the testing strategy and infrastructure for acs-must-gather.

## Overview

The testing framework is modeled after the stackrox/stackrox repository's comprehensive CI/CD approach, adapted for a must-gather container image project.

## Test Types

### 1. Shellcheck (Style/Lint)
**Purpose**: Static analysis of all shell scripts  
**Run**: `make lint`  
**CI**: Runs on every PR and push to main

Checks for:
- Shell syntax errors
- Common pitfalls and anti-patterns
- Portability issues
- Unused variables
- Quote issues

### 2. Syntax Validation
**Purpose**: Verify all scripts have valid bash syntax  
**Run**: `make validate`  
**CI**: Runs on every PR

Checks:
- `bash -n` on all collection scripts
- No syntax errors
- Scripts can be parsed

### 3. Permission Checks
**Purpose**: Ensure executable permissions are set correctly  
**Run**: `make check-permissions`  
**CI**: Runs on every PR

Checks:
- All `collection-scripts/gather*` files are executable
- Files without execute permission fail the check

### 4. Unit Tests
**Purpose**: Test individual shell functions in isolation  
**Framework**: [bats-core](https://github.com/bats-core/bats-core)  
**Run**: `make test-unit`  
**CI**: Runs on every PR

**Test Files**: `tests/unit/*.bats`

**Current Coverage**:
- `common.bats` - Tests for `collection-scripts/common.sh`
  - `log_msg()` function
  - `get_log_collection_args()` function
  - `resource_exists()` function
  - `discover_*()` functions

**Installing bats**:
```bash
# macOS
brew install bats-core

# Ubuntu/Debian
sudo apt-get install bats

# RHEL/Fedora
sudo dnf install bats
```

### 5. Integration Tests
**Purpose**: Test complete must-gather execution in a real environment  
**Run**: `make test-integration`  
**CI**: Runs on PRs only (requires cluster)

**Test Flow**:
1. Deploy mock RHACS installation (Central, Sensor, Collector)
2. Run must-gather container
3. Validate output structure and content

**Components**:
- `tests/integration/deploy-test-rhacs.sh` - Deploy test RHACS
- `tests/integration/run-must-gather.sh` - Execute must-gather
- `tests/integration/validate-output.sh` - Validate output

**Requirements**:
- Kind cluster (CI uses kind-action)
- kubectl access
- Container runtime (Docker/Podman)

### 6. Container Build Test
**Purpose**: Verify image builds successfully  
**Run**: `make build`  
**CI**: Runs on every PR and main push

Ensures:
- Dockerfile is valid
- Image builds without errors
- Image is tagged correctly

### 7. PR Title Format Check
**Purpose**: Enforce conventional commit format for PRs  
**Run**: Automatic on PR creation/update  
**CI**: Runs on every PR

**Accepted Formats**:
```
feat: Add diagnostic bundle collection
fix: Correct namespace discovery
docs: Update README with new features
chore: Update dependencies
refactor: Simplify gather script
test: Add unit tests for common functions
```

Or descriptive titles (10+ characters, starting with capital letter).

## CI/CD Pipeline

### GitHub Actions Workflow

**File**: `.github/workflows/ci.yaml`

**Triggers**:
- Push to `main` branch
- Pull request (opened, reopened, synchronize)

**Jobs**:

1. **shellcheck** - Run shellcheck on all scripts
2. **validate-scripts** - Syntax validation, whitespace check, permissions
3. **build-image** - Build container image and save as artifact
4. **unit-tests** - Run bats unit tests
5. **integration-tests** - Deploy test RHACS and run must-gather (PRs only)
6. **pr-title-check** - Validate PR title format (PRs only)
7. **summary** - Aggregate results and fail if any required job failed

**Concurrency**: Cancel in-progress runs when new commits are pushed

### Required Checks

For a PR to be mergeable:
- ✅ Shellcheck must pass
- ✅ Script validation must pass
- ✅ Image must build successfully
- ✅ Unit tests must pass (if they exist)
- ⚠️ Integration tests are optional (may not have cluster)
- ⚠️ PR title check is informational

## Running Tests Locally

### Quick CI Check
```bash
make ci
```

Runs: lint + validate + check-permissions + unit tests

### All Tests
```bash
make test
```

Runs: lint + unit tests

### Individual Test Suites

```bash
# Shellcheck only
make lint

# Syntax validation
make validate

# Permission check
make check-permissions

# Unit tests
make test-unit

# Integration tests (requires cluster)
make test-integration
```

### Running Specific Unit Tests

```bash
# All unit tests
bats tests/unit/*.bats

# Specific test file
bats tests/unit/common.bats

# Specific test case
bats tests/unit/common.bats --filter "log_msg"
```

## Writing Tests

### Unit Test Template

Create `tests/unit/<component>.bats`:

```bash
#!/usr/bin/env bats

# Unit tests for collection-scripts/<component>.sh

setup() {
    # Setup test environment
    export MUST_GATHER_DIR="/tmp/test-$$"
    mkdir -p "$MUST_GATHER_DIR"
    
    # Source script under test
    source "${BATS_TEST_DIRNAME}/../../collection-scripts/<component>.sh"
}

teardown() {
    # Cleanup
    rm -rf "$MUST_GATHER_DIR"
}

@test "function does what it should" {
    # Arrange
    local input="test"
    
    # Act
    result=$(function_under_test "$input")
    
    # Assert
    [[ "$result" == "expected" ]]
}

@test "function handles errors" {
    # Mock external command
    oc() {
        return 1  # Simulate failure
    }
    export -f oc
    
    # Should fail gracefully
    run function_that_calls_oc
    
    [[ "$status" -ne 0 ]]
}
```

### Integration Test Template

Create `tests/integration/<test-name>.sh`:

```bash
#!/bin/bash

set -euo pipefail

echo "==> Test: <description>"

# Setup
# ... create test resources

# Execute
# ... run must-gather or component

# Validate
# ... check output

echo "==> Test passed"
```

### Best Practices

1. **Isolation**: Each test should be independent
2. **Mock external commands**: Use shell functions to mock `oc`, `kubectl`, etc.
3. **Cleanup**: Always clean up in `teardown()`
4. **Descriptive names**: Test names should describe what they test
5. **Fast**: Unit tests should run in milliseconds
6. **Deterministic**: Tests should never be flaky

## Test Coverage Goals

### Current Coverage
- ✅ Shellcheck on all scripts
- ✅ Syntax validation
- ✅ Permission checks
- ✅ Basic unit tests for common.sh
- ✅ Integration test framework
- ✅ PR title format check

### Future Coverage Goals
- [ ] Unit tests for all collection scripts
- [ ] Integration tests for each gather_* script
- [ ] Test different RHACS versions
- [ ] Test error conditions (Central down, missing permissions, etc.)
- [ ] Test diagnostic bundle collection with auth
- [ ] Test debug dump collection
- [ ] Performance tests (collection time, bundle size)
- [ ] Regression tests (ensure old bundles still work)

## Continuous Integration

### Branch Protection

Main branch is protected with the following rules:
- ❌ No direct commits (must use PRs)
- ❌ No force pushes
- ❌ Cannot delete branch
- ✅ All changes via pull requests

### CI Status Checks

The following checks must pass before merging:
1. **Shellcheck** - Required
2. **Script Validation** - Required
3. **Build Image** - Required
4. **Unit Tests** - Required (when tests exist)
5. **Integration Tests** - Optional (informational)
6. **PR Title** - Optional (informational)

## Troubleshooting

### Shellcheck Fails
```bash
# Run locally to see issues
make lint

# Fix common issues:
# - Add quotes around variables: "$VAR" not $VAR
# - Use [[ ]] instead of [ ]
# - Add shellcheck disable comments if needed:
#   # shellcheck disable=SC2086
```

### Unit Tests Fail
```bash
# Run with verbose output
bats --tap tests/unit/common.bats

# Run single test
bats tests/unit/common.bats --filter "test name"

# Debug test
# Add 'set -x' to test function to see execution
```

### Integration Tests Fail
```bash
# Check cluster is accessible
kubectl cluster-info

# Check pods are running
kubectl get pods -n stackrox

# Run integration tests step-by-step
bash -x tests/integration/deploy-test-rhacs.sh
bash -x tests/integration/run-must-gather.sh
bash -x tests/integration/validate-output.sh
```

### Permission Issues
```bash
# Fix permissions
chmod +x collection-scripts/gather*

# Verify
make check-permissions
```

## Manual Testing

### Local Cluster Test
```bash
# 1. Build image
make build

# 2. Deploy test RHACS
kubectl apply -f tests/fixtures/test-rhacs.yaml

# 3. Run must-gather
oc adm must-gather --image=acs-must-gather:latest

# 4. Inspect output
ls -la must-gather*/
```

### Real Cluster Test
```bash
# Build and push
make push

# Run on real RHACS cluster
oc adm must-gather --image=quay.io/rhn_support_shaising/acs-must-gather:latest

# Validate output
bash tests/integration/validate-output.sh must-gather.local*/
```

## References

- [bats-core documentation](https://bats-core.readthedocs.io/)
- [shellcheck](https://www.shellcheck.net/)
- [GitHub Actions](https://docs.github.com/en/actions)
- [OpenShift must-gather](https://docs.openshift.com/container-platform/latest/support/gathering-cluster-data.html)
- [stackrox/stackrox CI](https://github.com/stackrox/stackrox/tree/master/.github/workflows)
