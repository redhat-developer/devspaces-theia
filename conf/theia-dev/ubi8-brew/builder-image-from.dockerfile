# https://access.redhat.com/containers/?tab=tags#/registry.access.redhat.com/ubi8/nodejs-12
FROM registry.access.redhat.com/ubi8/nodejs-12:1-102.1638363923
USER 0
RUN yum -y -q update && \
    yum -y -q clean all && rm -rf /var/cache/yum