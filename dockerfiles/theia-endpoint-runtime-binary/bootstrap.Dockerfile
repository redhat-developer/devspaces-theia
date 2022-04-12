# Copyright (c) 2019-21 Red Hat, Inc.
# This program and the accompanying materials are made
# available under the terms of the Eclipse Public License 2.0
# which is available at https://www.eclipse.org/legal/epl-2.0/
#
# SPDX-License-Identifier: EPL-2.0
#
# Contributors:
#   Red Hat, Inc. - initial API and implementation

FROM quay.io/eclipse/che-custom-nodejs-deasync:14.19.0 as custom-nodejs
FROM eclipse/che-theia:next as builder
ARG NEXE_SHA1=0f0869b292f1d7b68ba6e170d628de68a10c009f

WORKDIR /home/theia

# Apply node libs installed globally to the PATH
ENV PATH=${HOME}/.yarn/bin:${PATH}

# setup extra stuff
ENV NEXE_FLAGS="--target 'alpine-x64-14' --temp /tmp/nexe-cache"

COPY --from=custom-nodejs /alpine-x64-14 /tmp/nexe-cache/alpine-x64-14

USER root
# setup nexe
# install specific nexe
WORKDIR /tmp
RUN git clone https://github.com/nexe/nexe
WORKDIR /tmp/nexe
RUN git checkout ${NEXE_SHA1} && npm install && npm run build
# Change back to root folder
WORKDIR /home/theia

RUN /tmp/nexe/index.js -v && \
    # Build remote binary with node runtime 14.x and che-theia node dependencies. nexe icludes to the binary only
    # necessary dependencies.
    eval /tmp/nexe/index.js -i node_modules/@eclipse-che/theia-remote/lib/node/plugin-remote.js ${NEXE_FLAGS} -o ${HOME}/plugin-remote-endpoint

# Light image without node. We include remote binary to this image.
# https://access.redhat.com/containers/?tab=tags#/registry.access.redhat.com/ubi8-minimal
FROM registry.access.redhat.com/ubi8-minimal:8.5-240.1648458092 as runtime
USER 0
RUN microdnf -y install yum python38 python38-pyyaml jq && python3 --version && \
    yum -y -q update && \
    yum -y -q clean all && rm -rf /var/cache/yum && \
    echo "Installed Packages" && rpm -qa | sort -V && echo "End Of Installed Packages"
# collect yq dependency wheels for offline install
RUN python3 -m pip download yq -d /tmp

# Setup extra stuff
# install yq from local wheels we fetched earlier 
RUN pip3 --version && pip3 install /tmp/*.whl && yq --version && rm -fr /tmp/*.whl 

COPY --from=builder /home/theia/plugin-remote-endpoint /plugin-remote-endpoint

COPY src/entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
