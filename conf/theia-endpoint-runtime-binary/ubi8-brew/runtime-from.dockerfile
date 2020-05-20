FROM registry.access.redhat.com/ubi8-minimal:latest as runtime
USER 0
RUN microdnf update -y nodejs npm kernel-headers systemd && microdnf clean all && rm -rf /var/cache/yum && \
    echo "Installed Packages" && rpm -qa | sort -V && echo "End Of Installed Packages"
