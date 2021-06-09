# Copyright (c) 2020 Red Hat, Inc.
# This program and the accompanying materials are made
# available under the terms of the Eclipse Public License 2.0
# which is available at https://www.eclipse.org/legal/epl-2.0/
#
# SPDX-License-Identifier: EPL-2.0
#
# Contributors:
#   Red Hat, Inc. - initial API and implementation
#

# https://access.redhat.com/containers/?tab=tags#/registry.access.redhat.com/ubi8/nodejs-12
FROM registry.access.redhat.com/ubi8/nodejs-12:1-67
USER 0
RUN yum -y -q update --nobest && \
    yum -y -q clean all && rm -rf /var/cache/yum && \
    echo "Installed Packages" && rpm -qa | sort -V && echo "End Of Installed Packages"

# this script requires a github personal access token
ARG GITHUB_TOKEN=YOUR_TOKEN_HERE

RUN if [[ ${GITHUB_TOKEN} == "YOUR_TOKEN_HERE" ]]; then \
  echo; echo "ERROR: Must run this build with a valid GITHUB_TOKEN, eg.,"; \
  echo; \
  echo "  podman build -t crw-theia-builder . -f Dockerfile --build-arg GITHUB_TOKEN=cafef00dd00dbabebeaddabbadd00"; \
  echo; exit 1; \
fi

# set alternate branches and versions if required
ARG CHE_THEIA_BRANCH=7.17.x
ARG THEIA_BRANCH=master
ARG NODE_VERSION=10.19.0
ARG YARN_VERSION=1.17.3
ENV NODEJS_VERSION=10 \
    PATH=$HOME/node_modules/.bin/:$HOME/.npm-global/bin/:/usr/bin:$PATH
WORKDIR /projects

# much love to https://stackoverflow.com/questions/54397706/how-to-output-a-multiline-string-in-dockerfile-with-a-single-command
RUN echo $'[centos8-AppStream] \n\
name=CentOS-8 - AppStream \n\
baseurl=http://mirror.centos.org/centos-8/8/AppStream/x86_64/os/\n\
gpgcheck=0\n\
enabled=1\n\
\n\
[centos8-BaseOS]\n\
name=CentOS-8 - AppStream\n\
baseurl=http://mirror.centos.org/centos-8/8/BaseOS/x86_64/os/\n\
gpgcheck=0\n\
enabled=1\n\
' >> /etc/yum.repos.d/centos8.repo && cat /etc/yum.repos.d/centos8.repo && \
    # do we need java-1.8.0-openjdk?
    yum install --nogpgcheck -y jq wget curl tar gzip bzip2 python36 podman buildah skopeo containers-common
RUN pushd /usr/bin; rm -f python; ln -s ./python36 python; popd && whereis python && echo "PATH = $PATH" && \
    /usr/bin/python3 --version && \
    ln -s /usr/bin/podman /usr/bin/docker && \
    echo "NOTE: using podman as drop-in repacement for docker in /usr/bin" && \
    podman --version && docker --version && \
    buildah --version && skopeo --version
RUN npm install -g node@${NODE_VERSION} yarn@${YARN_VERSION} && \
    echo -n "node " && node --version && \
    echo -n "yarn " && yarn --version && \
    ln -s /usr/bin/node /usr/bin/nodejs && \
    for f in "${HOME}" "/opt/app-root/src/.npm-global"; do \
      chgrp -R 0 ${f} && \
      chmod -R g+rwX ${f}; \
    done
COPY build.sh conf ./

# switch from overlay to vfs in case we're in nested container hell
RUN sed -i /etc/containers/storage.conf -re 's|driver = .+|driver = "vfs"|'
RUN ./build.sh --ctb ${CHE_THEIA_BRANCH} --tb ${THEIA_BRANCH} --all \
      --no-tests --no-cache
