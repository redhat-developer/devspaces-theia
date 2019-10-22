ENV YARN_FLAGS="--offline"
COPY asset-theia-endpoint-runtime-yarn.tar.gz asset-download-dependencies.tar.gz /tmp/
RUN tar xzf /tmp/asset-theia-endpoint-runtime-yarn.tar.gz -C / && rm -f /tmp/asset-theia-endpoint-runtime-yarn.tar.gz && \
    tar xzf /tmp/asset-download-dependencies.tar.gz -C / && rm -f /tmp/asset-download-dependencies.tar.gz

COPY asset-workspace-yarn.lock /home/workspace/yarn.lock
COPY asset-theia-remote-yarn.lock /home/workspace/packages/theia-remote/yarn.lock

COPY asset-moxios.tgz /tmp/
RUN mkdir -p /tmp/moxios && tar xzf /tmp/asset-moxios.tgz -C /tmp/moxios && rm -f /tmp/asset-moxios.tgz
COPY asset-node-headers.tar.gz ${HOME}/asset-node-headers.tar.gz

# Patch github link to a local link 
RUN sed -i -e 's|moxios "git://github.com/stoplightio/moxios#v1.3.0"|moxios "file:///tmp/moxios"|' /home/workspace/yarn.lock \
    && sed -i -e "s|git://github.com/stoplightio/moxios#v1.3.0|file:///tmp/moxios|" /home/workspace/yarn.lock \
     && npm config set tarball ${HOME}/asset-node-headers.tar.gz