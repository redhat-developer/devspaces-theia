# revert offline mode (put back previous DNS resolution)
RUN rm -f /etc/resolv.conf && mv /etc/resolv.conf{.BAK,} || true
