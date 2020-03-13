# https://access.redhat.com/containers/?tab=tags#/registry.access.redhat.com/ubi8-minimal
FROM registry.access.redhat.com/ubi8-minimal:8.1-398 as runtime
RUN microdnf update -y systemd && microdnf clean all && rm -rf /var/cache/yum
