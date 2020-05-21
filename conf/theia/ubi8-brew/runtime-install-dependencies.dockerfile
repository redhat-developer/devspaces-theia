# need root user
USER root

# Copy sshpass sources
COPY asset-sshpass.tar.gz /tmp/

# Install sudo
# Install bzip2 to unpack files
# Install git
# Install which tool in order to search git
# Install curl and bash
# Install ssh for cloning ssh-repositories
# Install less for handling git diff properly
# Install sshpass for handling passwords for SSH keys
RUN yum install -y sudo git bzip2 which bash curl openssh less && tar -xvf /tmp/asset-sshpass.tar.gz && \
    cd /tmp/sshpass-*/ && ./configure && make install && cd .. && rm -rf sshpass-* && \
    echo "Installed Packages" && rpm -qa | sort -V && echo "End Of Installed Packages"
