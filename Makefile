IMAGE_REPO ?= quay.io/rhn_support_shaising
IMAGE_NAME ?= acs-must-gather
IMAGE_TAG  ?= latest
IMAGE      := $(IMAGE_REPO)/$(IMAGE_NAME):$(IMAGE_TAG)

.PHONY: build push lint test test-shell test-integration check-bundles validate analyze clean

build:
	podman build --platform linux/amd64 -t $(IMAGE) .

push: build
	podman push $(IMAGE)

lint:
	find collection-scripts -type f -exec shellcheck {} +
	python3 -m py_compile analysis/acs-analyze

test:
	python3 -m unittest discover -s tests -p 'test_*.py' -v

test-shell:
	bats tests/common.bats

test-integration:
	bats tests/integration.bats

check-bundles:
	bash scripts/check-no-bundles.sh

# Run every offline check (no cluster needed): lint, all tests, bundle guard.
validate: lint test test-shell test-integration check-bundles

# Analyze an extracted must-gather: make analyze BUNDLE=path/to/must-gather
analyze:
	python3 analysis/acs-analyze $(BUNDLE)

clean:
	podman rmi $(IMAGE) 2>/dev/null || true
