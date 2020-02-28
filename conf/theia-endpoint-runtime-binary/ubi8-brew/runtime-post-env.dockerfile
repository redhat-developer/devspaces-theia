ENV SUMMARY="Red Hat CodeReady Workspaces - Theia endpoint binary container" \
    DESCRIPTION="Red Hat CodeReady Workspaces - Theia endpoint binary container" \
    PRODNAME="codeready-workspaces" \
    COMPNAME="theia-endpoint-binary-rhel8" 

LABEL summary="$SUMMARY" \
      description="$DESCRIPTION" \
      io.k8s.description="$DESCRIPTION" \
      io.k8s.display-name="$DESCRIPTION" \
      io.openshift.tags="$PRODNAME,$COMPNAME" \
      com.redhat.component="$PRODNAME-$COMPNAME-container" \
      name="$PRODNAME/$COMPNAME" \
      version="2.1-20" \
      license="EPLv2" \
      maintainer="Nick Boldt <nboldt@redhat.com>" \
      io.openshift.expose-services="" \
      usage=""
