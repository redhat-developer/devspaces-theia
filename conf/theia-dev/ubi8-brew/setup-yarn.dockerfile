# Include yarn assets
COPY asset-yarn-*.tgz /tmp/
RUN tar xzf /tmp/asset-yarn-$(uname -m).tgz -C / && rm -f /tmp/asset-yarn-*.tgz
