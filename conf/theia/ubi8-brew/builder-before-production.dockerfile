# revert offline mode (put back previous DNS resolution)
RUN mv /etc/resolv.conf{.BAK,}
