# Base image pinned by digest for reproducible, supply-chain-safe builds.
# Digest resolved from quay.io/openshift/origin-must-gather:latest (2026-08-14).
# To update: re-resolve the digest for the desired tag, e.g.
#   skopeo inspect docker://quay.io/openshift/origin-must-gather:latest
# and replace the sha256 below.
FROM quay.io/openshift/origin-must-gather@sha256:1048ae58f60064a4e739681f3880954e886aa60178631bfbdbca6a5f584cb920

RUN dnf install -y jq && dnf clean all

COPY collection-scripts/* /usr/bin/

# Exec form so signals (SIGTERM/SIGINT) reach the gather process directly.
ENTRYPOINT ["/usr/bin/gather"]
