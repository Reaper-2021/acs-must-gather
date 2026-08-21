# Base: quay.io/openshift/origin-must-gather:latest (CentOS Stream 10).
# Pinned by digest for reproducible builds and scans. Bump this digest to pick
# up a newer base -- in particular once OpenShift rebuilds `oc` against patched
# github.com/docker/docker and github.com/moby/buildkit (the HIGH findings Quay
# reports live inside the upstream `oc` binary, not in anything installed here).
FROM quay.io/openshift/origin-must-gather@sha256:1048ae58f60064a4e739681f3880954e886aa60178631bfbdbca6a5f584cb920

# Patch OS packages first, then add the tools our collectors need. Drop all dnf
# caches/metadata afterwards to keep the layer small and scan-clean.
RUN dnf -y upgrade --refresh \
    && dnf -y install jq unzip openssl \
    && dnf clean all \
    && rm -rf /var/cache/dnf /var/lib/dnf/history*

COPY collection-scripts/* /usr/bin/

ENTRYPOINT /usr/bin/gather
