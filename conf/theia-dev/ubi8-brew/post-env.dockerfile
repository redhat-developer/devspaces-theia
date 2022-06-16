ENV YARN_FLAGS="--offline"

ENV SUMMARY="Red Hat OpenShift Dev Spaces - theia-dev container" \
    DESCRIPTION="Red Hat OpenShift Dev Spaces - theia-dev container" \
    PRODNAME="devspaces" \
    COMPNAME="theia-dev-rhel8" 

LABEL summary="$SUMMARY" \
      description="$DESCRIPTION" \
      io.k8s.description="$DESCRIPTION" \
      io.k8s.display-name="$DESCRIPTION" \
      io.openshift.tags="$PRODNAME,$COMPNAME" \
      com.redhat.component="$PRODNAME-$COMPNAME-container" \
      name="$PRODNAME/$COMPNAME" \
      version="@@DS_VERSION@@" \
      license="EPLv2" \
      maintainer="Nick Boldt <nboldt@redhat.com>" \
      io.openshift.expose-services="" \
      usage=""
