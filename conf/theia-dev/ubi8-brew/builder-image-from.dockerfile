# https://access.redhat.com/containers/?tab=tags#/registry.access.redhat.com/ubi8/nodejs-12
FROM registry.access.redhat.com/ubi8/nodejs-12:1-64
USER 0
RUN yum update -y freetype freetype-devel gnutls nodejs npm kernel-headers systemd && yum clean all && rm -rf /var/cache/yum
