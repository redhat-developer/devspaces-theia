# revert offline mode (put back previous DNS resolution)
# comment out -- this fails with "Device or resource busy"
# RUN rm -f /etc/resolv.conf && mv /etc/resolv.conf{.BAK,} || true
