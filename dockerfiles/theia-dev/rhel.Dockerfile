# Copyright (c) 2018-2021 Red Hat, Inc.
# This program and the accompanying materials are made
# available under the terms of the Eclipse Public License 2.0
# which is available at https://www.eclipse.org/legal/epl-2.0/
#
# SPDX-License-Identifier: EPL-2.0
#
# Contributors:
#   Red Hat, Inc. - initial API and implementation

###
# Theia dev Image
#
# https://access.redhat.com/containers/?tab=tags#/registry.access.redhat.com/ubi8/nodejs-12
FROM registry.access.redhat.com/ubi8/nodejs-12:1-90
USER 0
RUN yum -y -q update --nobest && \
    yum -y -q clean all && rm -rf /var/cache/yum

# Install packages
USER root
RUN yum install -y curl make cmake gcc gcc-c++ python2 git openssh less bash tar gzip libsecret libsecret-devel \
    && yum -y clean all && rm -rf /var/cache/yum && \
    ln -s /usr/bin/python2.7 /usr/bin/python; python --version && \
    echo "Installed Packages" && rpm -qa | sort -V && echo "End Of Installed Packages"

# setup yarn (if missing)
# Include yarn assets
COPY asset-yarn-*.tgz /tmp/
RUN tar xzf /tmp/asset-yarn-$(uname -m).tgz -C / && rm -f /tmp/asset-yarn-*.tgz

# Add npm global bin directory to the path
ENV HOME=/home/theia-dev \
    PATH=/home/theia-dev/.npm-global/bin:${PATH} \
    # Specify the directory of git (avoid to search at init of Theia)
    USE_LOCAL_GIT=true \
    LOCAL_GIT_DIRECTORY=/usr \
    GIT_EXEC_PATH=/usr/libexec/git-core \
    THEIA_ELECTRON_SKIP_REPLACE_FFMPEG=true \
    ELECTRON_SKIP_BINARY_DOWNLOAD=1 \
    YARN_FLAGS=""

# setup extra stuff
ENV YARN_FLAGS="--offline"

ENV SUMMARY="Red Hat CodeReady Workspaces - theia-dev container" \
    DESCRIPTION="Red Hat CodeReady Workspaces - theia-dev container" \
    PRODNAME="codeready-workspaces" \
    COMPNAME="theia-dev-rhel8" 

LABEL summary="$SUMMARY" \
      description="$DESCRIPTION" \
      io.k8s.description="$DESCRIPTION" \
      io.k8s.display-name="$DESCRIPTION" \
      io.openshift.tags="$PRODNAME,$COMPNAME" \
      com.redhat.component="$PRODNAME-$COMPNAME-container" \
      name="$PRODNAME/$COMPNAME" \
      version="2.10" \
      license="EPLv2" \
      maintainer="Nick Boldt <nboldt@redhat.com>" \
      io.openshift.expose-services="" \
      usage=""

# Define package of the theia generator to use
COPY asset-unpacked-generator ${HOME}/eclipse-che-theia-generator

WORKDIR ${HOME}

# Exposing Theia ports
EXPOSE 3000 3030

# Configure npm and yarn to use home folder for global dependencies
RUN npm config set prefix "${HOME}/.npm-global" && \
    echo "--global-folder \"${HOME}/.yarn-global\"" > ${HOME}/.yarnrc && \
    yarn config set network-timeout 600000 -g && \
    # add eclipse che-theia generator
    yarn ${YARN_FLAGS} global add yo generator-code vsce @theia/generator-plugin@0.0.1-1622834185 file:${HOME}/eclipse-che-theia-generator && \
    rm -rf ${HOME}/eclipse-che-theia-generator && \
    # Generate .passwd.template \
    cat /etc/passwd | \
    sed s#root:x.*#theia-dev:x:\${USER_ID}:\${GROUP_ID}::${HOME}:/bin/bash#g \
    > ${HOME}/.passwd.template && \
    # Generate .group.template \
    cat /etc/group | \
    sed s#root:x:0:#root:x:0:0,\${USER_ID}:#g \
    > ${HOME}/.group.template && \
    mkdir /projects && \
    # Define default prompt
    echo "export PS1='\[\033[01;33m\](\u@container)\[\033[01;36m\] (\w) \$ \[\033[00m\]'" > ${HOME}/.bashrc  && \
    # Disable the statistics for yeoman
    mkdir -p ${HOME}/.config/insight-nodejs/ && \
    echo '{"optOut": true}' > ${HOME}/.config/insight-nodejs/insight-yo.json && \
    # Change permissions to let any arbitrary user
    for f in "${HOME}" "/etc/passwd" "/etc/group" "/projects"; do \
        echo "Changing permissions on ${f}" && chgrp -R 0 ${f} && \
        chmod -R g+rwX ${f}; \
    done

# post yarn config
RUN echo "Installed npm Packages" && npm ls -g | sort | uniq || true
RUN yarn global list || true
RUN echo "End Of Installed npm Packages"

WORKDIR /projects

COPY src/entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

CMD tail -f /dev/null
