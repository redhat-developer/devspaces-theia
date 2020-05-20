FROM registry.access.redhat.com/ubi8/nodejs-10:latest as runtime
USER 0
RUN yum update -y nodejs npm kernel-headers systemd && yum clean all && rm -rf /var/cache/yum && \
    echo "Installed Packages" && rpm -qa | sort -V && echo "End Of Installed Packages"
