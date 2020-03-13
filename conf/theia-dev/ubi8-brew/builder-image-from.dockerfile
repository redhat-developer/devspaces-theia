# https://access.redhat.com/containers/?tab=tags#/registry.access.redhat.com/ubi8/nodejs-10
FROM registry.access.redhat.com/ubi8/nodejs-10:1-66
USER 0
RUN yum update -y systemd && yum clean all && rm -rf /var/cache/yum
