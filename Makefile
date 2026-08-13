IMAGE_REPO ?= quay.io/rhn_support_shaising
IMAGE_NAME ?= acs-must-gather
IMAGE_TAG  ?= latest
IMAGE      := $(IMAGE_REPO)/$(IMAGE_NAME):$(IMAGE_TAG)
LOCAL_IMAGE := $(IMAGE_NAME):$(IMAGE_TAG)

.PHONY: build push lint clean test-unit test-integration test validate check-permissions ci help

build:
	podman build --platform linux/amd64 -t $(LOCAL_IMAGE) -t $(IMAGE) .

push: build
	podman push $(IMAGE)

lint:
	@echo "Running shellcheck on collection scripts..."
	@find collection-scripts -type f -exec shellcheck {} +
	@echo "✓ Shellcheck passed"

test-unit:
	@echo "Running unit tests..."
	@if command -v bats >/dev/null 2>&1; then \
		bats tests/unit/*.bats; \
	else \
		echo "ERROR: bats not installed. Install with: brew install bats-core (macOS) or apt-get install bats (Linux)"; \
		exit 1; \
	fi

test-integration: build
	@echo "Running integration tests..."
	@bash tests/integration/deploy-test-rhacs.sh
	@bash tests/integration/run-must-gather.sh
	@bash tests/integration/validate-output.sh

test: lint test-unit
	@echo "All tests passed!"

validate:
	@echo "Validating script syntax..."
	@for script in collection-scripts/*; do \
		if [[ -f "$$script" && -x "$$script" ]]; then \
			echo "  Checking: $$script"; \
			bash -n "$$script" || exit 1; \
		fi; \
	done
	@echo "✓ All scripts have valid syntax"

check-permissions:
	@echo "Checking executable permissions..."
	@for script in collection-scripts/gather*; do \
		if [[ ! -x "$$script" ]]; then \
			echo "ERROR: $$script is not executable"; \
			echo "Run: chmod +x $$script"; \
			exit 1; \
		fi; \
	done
	@echo "✓ All scripts have correct permissions"

ci: lint validate check-permissions test-unit
	@echo "✓ CI checks passed"

clean:
	podman rmi $(IMAGE) $(LOCAL_IMAGE) 2>/dev/null || true

help:
	@echo "ACS Must-Gather Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  build              - Build container image"
	@echo "  push               - Push image to registry"
	@echo "  lint               - Run shellcheck on all scripts"
	@echo "  test-unit          - Run unit tests (requires bats)"
	@echo "  test-integration   - Run integration tests (requires kind/cluster)"
	@echo "  test               - Run lint + unit tests"
	@echo "  validate           - Validate script syntax"
	@echo "  check-permissions  - Check executable permissions"
	@echo "  ci                 - Run all CI checks"
	@echo "  clean              - Remove built images"
	@echo "  help               - Show this help"
