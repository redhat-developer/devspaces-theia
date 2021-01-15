# https://access.redhat.com/containers/?tab=tags#/registry.access.redhat.com/ubi8-minimal
FROM registry.access.redhat.com/ubi8-minimal:8.3-230 as runtime
USER 0
# If required, could install yum and then do a global yum update -y for ALL rpms, rather than this subset
RUN microdnf update -y freetype freetype-devel gnutls nodejs npm kernel-headers systemd && microdnf clean all && rm -rf /var/cache/yum && \
    echo "Installed Packages" && rpm -qa | sort -V && echo "End Of Installed Packages"
