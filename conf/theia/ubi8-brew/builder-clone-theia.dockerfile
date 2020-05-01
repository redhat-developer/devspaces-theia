COPY asset-theia-source-code.tar.gz /tmp/asset-theia-source-code.tar.gz
RUN tar xzf /tmp/asset-theia-source-code.tar.gz -C ${HOME} && rm -f /tmp/asset-theia-source-code.tar.gz

#apply patch for Theia loader
ADD branding/loader/loader.patch ${HOME}
ADD branding/loader/CodeReady_icon_loader.svg ${HOME}/theia-source-code/packages/core/src/browser/icons/CodeReady_icon_loader.svg
# comment out patch https://github.com/eclipse/che/issues/16822
# RUN cd ${HOME}/theia-source-code && git apply ../loader.patch
