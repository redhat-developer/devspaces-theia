USER root
# Install libsecret as Theia requires it
# Install libsecret-devel on s390x and ppc64le for keytar build (binary included in npm package for x86)
RUN yum install -y curl make cmake gcc gcc-c++ python2 git git-core-doc openssh less bash tar gzip rsync patch \
    libsecret libsecret-devel \
    && yum -y clean all && rm -rf /var/cache/yum && \
    ln -s /usr/bin/python2.7 /usr/bin/python; python --version && \
    echo "Installed Packages" && rpm -qa | sort -V && echo "End Of Installed Packages"
