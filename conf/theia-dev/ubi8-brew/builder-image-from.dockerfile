# https://access.redhat.com/containers/?tab=tags#/registry.access.redhat.com/ubi8/nodejs-12
FROM registry.access.redhat.com/ubi8/nodejs-12:1-102
USER 0
RUN yum -y -q update --nobest && \
    yum -y -q clean all && rm -rf /var/cache/yum