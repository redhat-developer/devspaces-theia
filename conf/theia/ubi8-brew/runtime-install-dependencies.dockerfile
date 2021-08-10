# need root user
USER root

# Copy sshpass sources
COPY asset-sshpass-sources.tar.gz /tmp/

# Install sudo
# Install git
# Install bzip2 to unpack files
# Install which tool in order to search git
# Install curl and bash
# Install ssh for cloning ssh-repositories
# Install less for handling git diff properly
# Install sshpass for handling passwords for SSH keys
# Install libsecret as Theia requires it
# Install libsecret-devel on s390x and ppc64le for keytar build (binary included in npm package for x86)
RUN yum install -y sudo git bzip2 which bash curl openssh less \
    libsecret libsecret-devel \
    && tar -xvf /tmp/asset-sshpass-sources.tar.gz -C /tmp/ && \
    cd /tmp/sshpass-*/ && ./configure && make install && cd .. && rm -rf *sshpass-* && \
    echo "Installed Packages" && rpm -qa | sort -V && echo "End Of Installed Packages"
