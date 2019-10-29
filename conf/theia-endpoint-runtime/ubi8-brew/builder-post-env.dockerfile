ENV YARN_FLAGS="--offline"
COPY asset-theia-endpoint-runtime-yarn.tar.gz asset-download-dependencies.tar.gz /tmp/
RUN tar xzf /tmp/asset-theia-endpoint-runtime-yarn.tar.gz -C / && rm -f /tmp/asset-theia-endpoint-runtime-yarn.tar.gz && \
    tar xzf /tmp/asset-download-dependencies.tar.gz -C / && rm -f /tmp/asset-download-dependencies.tar.gz

COPY asset-workspace-yarn.lock /home/workspace/yarn.lock
COPY asset-theia-remote-yarn.lock /home/workspace/packages/theia-remote/yarn.lock

# Use local file for node headers
COPY asset-node-headers.tar.gz ${HOME}/asset-node-headers.tar.gz
RUN npm config set tarball ${HOME}/asset-node-headers.tar.gz