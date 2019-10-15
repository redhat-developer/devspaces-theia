COPY asset-theia-source-code.tar.gz /tmp/asset-theia-source-code.tar.gz
RUN tar xzf /tmp/asset-theia-source-code.tar.gz -C ${HOME} && rm -f /tmp/asset-theia-source-code.tar.gz
