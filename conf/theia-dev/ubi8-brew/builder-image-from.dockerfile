FROM registry.access.redhat.com/ubi8/nodejs-10:latest
USER 0
RUN yum update -y nodejs npm kernel-headers systemd && yum clean all && rm -rf /var/cache/yum
