IMAGE_REPO ?= quay.io/rhacs-eng
IMAGE_NAME ?= acs-must-gather
IMAGE_TAG  ?= latest
IMAGE      := $(IMAGE_REPO)/$(IMAGE_NAME):$(IMAGE_TAG)

.PHONY: build push lint clean

build:
	podman build -t $(IMAGE) .

push: build
	podman push $(IMAGE)

lint:
	find collection-scripts -type f -exec shellcheck {} +

clean:
	podman rmi $(IMAGE) 2>/dev/null || true
