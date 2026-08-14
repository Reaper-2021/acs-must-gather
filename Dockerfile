FROM quay.io/openshift/origin-must-gather:latest

RUN dnf install -y jq unzip && dnf clean all

COPY collection-scripts/* /usr/bin/

ENTRYPOINT /usr/bin/gather
