#{IF:DO_REMOTE_CHECK}
# globally install node-gyp ahead of time. Note: theia depends on ^5.0 and ^3.8 but might install ^6.0
RUN ls -la /home/theia-dev/*
# must not fail here even for
#    error Package "" refers to a non-existing file '"/home/theia-dev/eclipse-che-theia-generator"'.
#    The command '/bin/sh -c yarn global add node-gyp' returned a non-zero code: 1
# so always return true
RUN yarn global add node-gyp || true
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
