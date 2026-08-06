FROM quay.io/openshift/origin-must-gather:latest

RUN dnf install -y jq && dnf clean all

COPY collection-scripts/* /usr/bin/

ENTRYPOINT /usr/bin/gather
