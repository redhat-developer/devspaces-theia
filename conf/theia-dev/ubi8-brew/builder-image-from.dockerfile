# https://access.redhat.com/containers/?tab=tags#/registry.access.redhat.com/ubi8/nodejs-14
FROM registry.access.redhat.com/ubi8/nodejs-14:1-99.1675799486
USER 0
RUN yum -y -q update && \
    yum -y -q clean all && rm -rf /var/cache/yum
