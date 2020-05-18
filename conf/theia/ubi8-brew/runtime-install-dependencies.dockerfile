# need root user
USER root

# Install sudo
# Install bzip2 to unpack files
# Install git
# Install which tool in order to search git
# Install curl and bash
# Install ssh for cloning ssh-repositories
# Install less for handling git diff properly
RUN yum install -y sudo bzip2 git which bash curl openssh less && \
    yum -y clean all && rm -rf /var/cache/yum && \
    echo "Installed Packages" && rpm -qa | sort -V && echo "End Of Installed Packages"
