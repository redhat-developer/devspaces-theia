# copy previously cached yq dependency wheels for offline install
COPY *.whl /tmp

ENV SUMMARY="Red Hat OpenShift Dev Spaces - theia-endpoint container" \
    DESCRIPTION="Red Hat OpenShift Dev Spaces - theia-endpoint container" \
    PRODNAME="devspaces" \
    COMPNAME="theia-endpoint-rhel8" 

LABEL summary="$SUMMARY" \
      description="$DESCRIPTION" \
      io.k8s.description="$DESCRIPTION" \
      io.k8s.display-name="$DESCRIPTION" \
      io.openshift.tags="$PRODNAME,$COMPNAME" \
      com.redhat.component="$PRODNAME-$COMPNAME-container" \
      name="$PRODNAME/$COMPNAME" \
      version="@@CRW_VERSION@@" \
      license="EPLv2" \
      maintainer="Nick Boldt <nboldt@redhat.com>" \
      io.openshift.expose-services="" \
      usage=""

