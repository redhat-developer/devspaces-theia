# Include yarn assets for runtime image
COPY asset-yarn-runtime-image.tar.gz /tmp/
RUN tar xzf /tmp/asset-yarn-runtime-image.tar.gz -C / && \
    rm -f /tmp/asset-yarn-runtime-image.tar.gz
