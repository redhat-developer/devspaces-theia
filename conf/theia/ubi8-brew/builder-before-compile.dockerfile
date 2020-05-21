#{IF:DO_REMOTE_CHECK}
# globally install node-gyp ahead of time. Note: theia depends on ^5.0 and ^3.8 but might install ^6.0
# unpack /home/theia-dev/eclipse-che-theia-generator.tgz into /home/theia-dev/eclipse-che-theia-generator so that the node-gyp install doesn't fail
RUN echo ${HOME} && cd ${HOME} && tar zxf eclipse-che-theia-generator.tgz && mv package eclipse-che-theia-generator && \
    ls -la /home/theia-dev/*

# do we also need to add file:${HOME}/eclipse-che-theia-generator
RUN yarn global add node-gyp 
RUN node-gyp install
RUN sed -i ${HOME}/theia-source-code/package.json -e 's@node-gyp install@echo skip node-gyp install@'
#ENDIF

COPY asset-yarn.tar.gz asset-post-download-dependencies.tar.gz /tmp/
RUN tar xzf /tmp/asset-yarn.tar.gz -C / && rm -f /tmp/asset-yarn.tar.gz && \
    tar xzf /tmp/asset-post-download-dependencies.tar.gz -C / && rm -f /tmp/asset-post-download-dependencies.tar.gz

# Copy yarn.lock to be the same than the previous build
COPY asset-yarn.lock ${HOME}/theia-source-code/yarn.lock

ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    puppeteer_skip_chromium_download=true

COPY asset-node-headers.tar.gz ${HOME}/asset-node-headers.tar.gz
RUN \
    # Use local file for node headers
    npm config set tarball ${HOME}/asset-node-headers.tar.gz && \
    # Disable puppeteer from downloading chromium
    npm config set puppeteer_skip_chromium_download true -g && \
    yarn config set puppeteer_skip_chromium_download true -g && \
    # Disable travis script
    echo "#!/usr/bin/env node" > /home/theia-dev/theia-source-code/scripts/prepare-travis \
    # Add offline mode in examples
    && sed -i -e "s|spawnSync('yarn', \[\]|spawnSync('yarn', \['--offline'\]|" ${HOME}/theia-source-code/plugins/foreach_yarn \
    # Disable automatic tests that connect online
    && for d in plugins/*/package.json; do echo "Disable 'yarn test' in $d"; sed -i -e "s/ && yarn test//" $d; done

# enable offline move (no DNS resolution)
# comment out -- this fails with "Device or resource busy"
# RUN mv /etc/resolv.conf{,.BAK} && echo "" > /etc/resolv.conf
RUN echo "" > /etc/resolv.conf || true
# kill all electron 
RUN rm -fr /home/theia-dev/theia-source-code/node_modules/*/electron /home/theia-dev/theia-source-code/node_modules/*electron* || true
