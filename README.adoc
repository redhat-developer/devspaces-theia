Links marked with this icon :door: are _internal to Red Hat_. This includes Jenkins servers, job configs in gitlab, and container sources in dist-git. 

# codeready-workspaces-theia
CodeReady Workspaces build of Theia, based on eclipse/che-theia project

## Create dockerfiles for theia in brew

`./build.sh` will:
- fetch che-theia
- generate `:next` tmp images from ubi8 config to be used for grabing assets
- generate into `dockerfiles` directory the assets / Dockerfile

Steps: 
- `./build.sh`
- check `dockerfiles` directory with ready-to-go Dockerfile with already included in folders

### NOTE

The Jenkinsfiles in this repo have moved. See:

* https://main-jenkins-csb-crwqe.apps.ocp4.prod.psi.redhat.com/job/CRW_CI/ (jobs) :door:
* https://gitlab.cee.redhat.com/codeready-workspaces/crw-jenkins/-/tree/master/jobs/CRW_CI (sources) :door:
* https://github.com/redhat-developer/codeready-workspaces-images#jenkins-jobs (copied sources)


## Branding

Branding is currently in two places.

### Dashboard

To reskin link:https://github.com/eclipse-che/che-dashboard/tree/main/assets/branding[Che Dashboard], see link:https://github.com/redhat-developer/codeready-workspaces-images/tree/crw-2-rhel-8/codeready-workspaces-dashboard/README.adoc[dashboard]

### Theia

To reskin link:https://github.com/eclipse-che/che-theia[Che Theia], see link:https://github.com/redhat-developer/codeready-workspaces-theia/tree/crw-2-rhel-8/conf/theia/branding[codeready-workspaces-theia/conf/theia/branding]. 

### A note about SVG files 

If using Inkscape to save files, make sure you export as *Plain SVG*, then edit the resulting .svg file to remove any `<metadata>...</metadata>` tags and all their contents. You can also remove the `xmlns:rdf` definition. This will ensure they compile correctly.