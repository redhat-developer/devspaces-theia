#Copy branding files
COPY branding ${HOME}/branding

ENV YARN_FLAGS="--offline"

ENV SUMMARY="Red Hat CodeReady Workspaces - Theia container" \
    DESCRIPTION="Red Hat CodeReady Workspaces - Theia container" \
    PRODNAME="codeready-workspaces" \
    COMPNAME="theia-rhel8" \
    PRODUCT_JSON=${HOME}/branding/product.json

LABEL summary="$SUMMARY" \
      description="$DESCRIPTION" \
      io.k8s.description="$DESCRIPTION" \
      io.k8s.display-name="$DESCRIPTION" \
      io.openshift.tags="$PRODNAME,$COMPNAME" \
      com.redhat.component="$PRODNAME-$COMPNAME-container" \
      name="$PRODNAME/$COMPNAME" \
      version="2.0" \
      license="EPLv2" \
      maintainer="Nick Boldt <nboldt@redhat.com>" \
      io.openshift.expose-services="" \
      usage=""
