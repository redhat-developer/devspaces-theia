#!/usr/bin/env groovy

import groovy.transform.Field

// PARAMETERS for this pipeline:
    // none

// https://issues.redhat.com/browse/CRW-1011 job to set up cdn / akamai stuff for the theia-rhel8 image

String MIDSTM_BRANCH = "crw-2.5-rhel-8" // target branch, eg., crw-2.5-rhel-8

def buildNode = "rhel7-32gb||rhel7-16gb||rhel7-8gb||rhel7-releng" // node label
timeout(30) {
    node("${buildNode}"){ 
        stage("Copy from OSBS to Quay") {
            wrap([$class: 'TimestamperBuildWrapper']) {
                sh('curl -sSLO https://raw.githubusercontent.com/redhat-developer/codeready-workspaces/'+ MIDSTM_BRANCH + '/product/util.groovy')
                def util = load "${WORKSPACE}/util.groovy"
                cleanWs()
                CRW_VERSION = util.getCrwVersion(MIDSTM_BRANCH)
                println "CRW_VERSION = '" + CRW_VERSION + "'"
                util.installSkopeo(CRW_VERSION)
                util.installYq()

                withCredentials([file(credentialsId:'che-akamai-auth', variable: 'AKAMAI_CHE_AUTH'),
                    file(credentialsId: 'crw-build.keytab', variable: 'CRW_KEYTAB')]) {
                    util.bootstrap(CRW_KEYTAB)

                    sh (
                        script: 'curl -sSLO https://raw.githubusercontent.com/redhat-developer/codeready-workspaces/'+MIDSTM_BRANCH+'/product/getLatestImageTags.sh && chmod +x getLatestImageTags.sh',
                        returnStdout: true).trim().split( '\n' )
                    sh (
                        script: 'curl -sSLO https://raw.githubusercontent.com/redhat-developer/codeready-workspaces/'+MIDSTM_BRANCH+'/product/getTagForImage.sh && chmod +x getTagForImage.sh',
                        returnStdout: true).trim().split( '\n' )

                    def latestTheiaImageTag = sh (
                            script: './getTagForImage.sh $(./getLatestImageTags.sh -b ' + MIDSTM_BRANCH + ' -c codeready-workspaces-theia-rhel8 --osbs)',
                            returnStdout: true
                        ).trim()
                    def latestTheiaImage = "registry-proxy.engineering.redhat.com/rh-osbs/codeready-workspaces-theia-rhel8:" + latestTheiaImageTag
                    currentBuild.description="Add CDN support for " + latestTheiaImageTag

                    sh('''#!/bin/bash -xe
echo "[INFO] Add CDN support for ''' + latestTheiaImage + '''"
set -x
set +e

cdn_folder="crw_theia_artifacts"
# debug info
docker container ls -all
# /home/theia/lib/cdn.json does not exist in 2.2-19 version of the container. See https://issues.redhat.com/browse/CRW-993
CDN_JSON=$(docker run --name theia-container --entrypoint /bin/bash "''' + latestTheiaImage + '''" -c "cat /home/theia/lib/cdn.json 2>/dev/null")
if [[ $? -eq 0 ]] && [[ ${CDN_JSON} ]]; then
for file in $(echo "${CDN_JSON}" | jq --raw-output '.[] | select((has("cdn")) and (has("external")|not)) | .chunk,.resource'  | grep -v 'null' )
do
    dir=$(dirname "$file")
    mkdir -p "$cdn_folder/$dir"
    docker cp "theia-container:/home/theia/lib/$file" "$cdn_folder/$file"
done

echo "[INFO] Files to push to Akamai storage:"
echo "[INFO] $(find "$cdn_folder" -type f -print)"

if [ -z "${AKAMAI_CHE_AUTH:-}" ]; then
    echo "[ERROR] CDN files will not be pushed to the Akamai directory since the 'AKAMAI_CHE_AUTH' environment variable is not set"
    exit 0
fi

echo "[INFO] Push CDN files to the Akamai directory"

for file in $(find "$cdn_folder" -type f -print); do
    echo "[INFO]    Push $file" 
    docker run -i --rm -v "${AKAMAI_CHE_AUTH}:/root/.akamai-cli/.netstorage/auth" -v "$(pwd)/$cdn_folder:/$cdn_folder" akamai/cli netstorage upload --directory "${AKAMAI_CHE_DIR:-che}" "${file}"
done
else
echo "[WARN] No /home/theia/lib/cdn.json found in ''' + latestTheiaImage + ''' -- cannot add CDN support!"
fi
docker rm "theia-container" >/dev/null
                    ''')
                    currentBuild.description="CDN support added for " + latestTheiaImageTag
                    } // with
            } // wrap
        } // stage
    } // node
} // timeout

