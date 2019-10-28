#{IF:DO_REMOTE_CHECK}
# globally install node-gyp ahead of time. Note: theia depends on ^5.0 and ^3.8 but might install ^6.0
RUN yarn global add node-gyp && node-gyp install && \
    sed -i ${HOME}/theia-source-code/package.json -e 's@node-gyp install@echo skip node-gyp install@'
#ENDIF

COPY asset-yarn.tar.gz asset-post-download-dependencies.tar.gz asset-moxios.tgz /tmp/
RUN tar xzf /tmp/asset-yarn.tar.gz -C / && rm -f /tmp/asset-yarn.tar.gz && \
    tar xzf /tmp/asset-post-download-dependencies.tar.gz -C / && rm -f /tmp/asset-post-download-dependencies.tar.gz && \
    mkdir -p /tmp/moxios && tar xzf /tmp/asset-moxios.tgz -C /tmp/moxios && rm -f /tmp/asset-moxios.tgz

COPY asset-node-headers.tar.gz ${HOME}/asset-node-headers.tar.gz

# Copy yarn.lock to be the same than the previous build
COPY asset-yarn.lock ${HOME}/theia-source-code/yarn.lock

RUN \
    # Define node headers
    npm config set tarball ${HOME}/asset-node-headers.tar.gz && \
    # Disable travis script
    echo "#!/usr/bin/env node" > /home/theia-dev/theia-source-code/scripts/prepare-travis \
    # Patch github link to a local link 
    && sed -i -e 's|moxios "git://github.com/stoplightio/moxios#v1.3.0"|moxios "file:///tmp/moxios"|' ${HOME}/theia-source-code/yarn.lock \
    && sed -i -e "s|git://github.com/stoplightio/moxios#v1.3.0|file:///tmp/moxios|" ${HOME}/theia-source-code/yarn.lock \
    # Add offline mode in examples
    && sed -i -e "s|spawnSync('yarn', \[\]|spawnSync('yarn', \['--offline'\]|" ${HOME}/theia-source-code/plugins/foreach_yarn \
    # Disable automatic tests that connect online
    && sed -i -e "s/ && yarn test//" plugins/factory-plugin/package.json 
