# https://access.redhat.com/containers/?tab=tags#/registry.access.redhat.com/ubi8/nodejs-10
FROM registry.access.redhat.com/ubi8/nodejs-10:1-99
USER 0
RUN yum update -y gnutls nodejs npm kernel-headers systemd && yum clean all && rm -rf /var/cache/yum
