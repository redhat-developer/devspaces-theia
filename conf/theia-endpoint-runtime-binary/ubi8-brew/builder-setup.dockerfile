USER root
ENV YARN_FLAGS="--offline"
ENV NEXE_FLAGS="--target 'alpine-x64-12' --temp /tmp/nexe-cache"
COPY asset-theia-endpoint-runtime-pre-assembly-nexe-cache-*.tar.gz asset-theia-endpoint-runtime-binary-yarn-*.tar.gz asset-node-src.tar.gz /tmp/
RUN tar xzf /tmp/asset-theia-endpoint-runtime-binary-yarn-$(uname -m).tar.gz -C / && rm -f /tmp/asset-theia-endpoint-runtime-binary-yarn-*.tar.gz && \
    export NODE_VERSION=$(node --version | sed -s 's/v//') && mkdir -p "/home/theia/.nexe/${NODE_VERSION}" && \
    tar zxf /tmp/asset-node-src.tar.gz --strip-components=1 -C "/home/theia/.nexe/${NODE_VERSION}" && \
    rm -f /tmp/asset-node-src.tar.gz && \
    tar zxf /tmp/asset-theia-endpoint-runtime-pre-assembly-nexe-cache-$(uname -m).tar.gz -C "/tmp/" && \
    rm -f /tmp/asset-theia-endpoint-runtime-pre-assembly-nexe-cache-*.tar.gz 

RUN yum install -y git make cmake gcc gcc-c++ python2 automake autoconf which glibc-devel && \
    yum -y clean all && rm -rf /var/cache/yum && ln -s /usr/bin/python2 /usr/bin/python
