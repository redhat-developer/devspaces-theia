# need root user
USER root

# Install sudo
# Install bzip2 to unpack files
# Install git
# Install which tool in order to search git
# Install curl and bash
# Install ssh for cloning ssh-repositories
# Install sshpass for handling passwordds for SSH keys
RUN yum install -y sudo git bzip2 which bash curl openssh less \
    wget http://sourceforge.net/projects/sshpass/files/latest/download -O sshpass.tar.gz && \
    tar -xvf sshpass.tar.gz && cd sshpass-1.06 && ./configure && make install cd .. && rm -rf sshpass-1.06 && \
    echo "Installed Packages" && rpm -qa | sort -V && echo "End Of Installed Packages"
