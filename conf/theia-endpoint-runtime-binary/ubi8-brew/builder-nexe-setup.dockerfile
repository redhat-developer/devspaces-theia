# install specific nexe
COPY asset-theia-endpoint-runtime-pre-assembly-nexe-*.tar.gz /tmp/
RUN tar zxf /tmp/asset-theia-endpoint-runtime-pre-assembly-nexe-$(uname -m).tar.gz -C "/tmp/" && \
    rm -f /tmp/asset-theia-endpoint-runtime-pre-assembly-nexe-*.tar.gz 
# Change back to root folder
WORKDIR /home/theia
