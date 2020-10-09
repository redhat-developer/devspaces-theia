#!/usr/bin/env groovy

import groovy.transform.Field

// PARAMETERS for this pipeline:
// SCRATCH = true (don't push to Quay) or false (do push to Quay)

@Field String DWNSTM_BRANCH = "crw-2.5-rhel-8" // branch in GH repo, eg., crw-2.5-rhel-8

def buildNode = "rhel7-releng" // node label
// def JOB_BRANCH = CRW_VERSION // computed below; used to differentiate job URLs

def MIDSTM_REPO = "https://github.com/redhat-developer/codeready-workspaces-theia.git" //source repo from which to find and sync commits to pkgs.devel repo
def DWNSTM_REPO1 = "ssh://crw-build@pkgs.devel.redhat.com/containers/codeready-workspaces-theia-dev" // dist-git repo to use as target
def DWNSTM_REPO2 = "ssh://crw-build@pkgs.devel.redhat.com/containers/codeready-workspaces-theia" // dist-git repo to use as target
def DWNSTM_REPO3 = "ssh://crw-build@pkgs.devel.redhat.com/containers/codeready-workspaces-theia-endpoint" // dist-git repo to use as target
def SYNC_FILES = "src etc"

def MIDSTM_BRANCH = DWNSTM_BRANCH
def QUAY_PROJECT1 = "theia-dev" // also used for the Brew dockerfile params
def QUAY_PROJECT2 = "theia" // also used for the Brew dockerfile params
def QUAY_PROJECT3 = "theia-endpoint" // also used for the Brew dockerfile params

def OLD_SHA1=""
def OLD_SHA2=""
def OLD_SHA3=""
def SRC_SHA1=""

def JOB_BRANCH="2.5"
def UPSTREAM_JOB_NAME="crw-theia-sources_${JOB_BRANCH}"
def jenkinsURL="https://codeready-workspaces-jenkins.rhev-ci-vms.eng.rdu2.redhat.com/job/${UPSTREAM_JOB_NAME}"
def assetPath="/lastSuccessfulBuild/artifact/crw-theia/dockerfiles/*zip*/dockerfiles.zip"

timeout(120) {
  node(buildNode) {
  stage ("Sync repos on ${buildNode}") {
    sh('curl -sSLO https://raw.githubusercontent.com/redhat-developer/codeready-workspaces/crw-2.5-rhel-8/product/util.groovy')
    def util = load "${WORKSPACE}/util.groovy"
    wrap([$class: 'TimestamperBuildWrapper']) {
      cleanWs()
      CRW_VERSION = util.getCrwVersion(DWNSTM_BRANCH)
      println "CRW_VERSION = '" + CRW_VERSION + "'"
      util.installSkopeo(CRW_VERSION)
      sh('pip install -I --user yq')
      yq_bin = sh(script: 'python -m site --user-base', returnStdout:true).trim() + '/bin/yq'

      withCredentials([string(credentialsId:'devstudio-release.token', variable: 'GITHUB_TOKEN'),
          file(credentialsId: 'crw-build.keytab', variable: 'CRW_KEYTAB')]) {
        util.bootstrap(CRW_KEYTAB)
        util.cloneRepo(MIDSTM_REPO, "crw-theia", MIDSTM_BRANCH)

        println("Retrieve dockerfiles from build and extract in crw-theia")
        sh('''#!/bin/bash +x
          cd ${WORKSPACE}/crw-theia
          curl -sSLO "''' + jenkinsURL + assetPath + '''"
          unzip -o dockerfiles.zip
          rm dockerfiles.zip
          ''')
        SRC_SHA1 = util.getLastCommitSHA("${WORKSPACE}/crw-theia")
        println "Got SRC_SHA1 in crw-theia folder: " + SRC_SHA1

        util.cloneRepo(DWNSTM_REPO1, "target1", DWNSTM_BRANCH)
        util.cloneRepo(DWNSTM_REPO2, "target2", DWNSTM_BRANCH)
        util.cloneRepo(DWNSTM_REPO3, "target3", DWNSTM_BRANCH)
        OLD_SHA1 = util.getLastCommitSHA("${WORKSPACE}/target1")
        OLD_SHA2 = util.getLastCommitSHA("${WORKSPACE}/target2")
        OLD_SHA3 = util.getLastCommitSHA("${WORKSPACE}/target3")

        println("Sync Changes and do Dockerfile transformations")
        sh('''#!/bin/bash -xe
          for targetN in target1 target2 target3; do
            if [[ \$targetN == "target1" ]]; then SRC_PATH="${WORKSPACE}/crw-theia/dockerfiles/''' + QUAY_PROJECT1 + '''"; fi
            if [[ \$targetN == "target2" ]]; then SRC_PATH="${WORKSPACE}/crw-theia/dockerfiles/''' + QUAY_PROJECT2 + '''"; fi
            # special case since folder created != quay image
            if [[ \$targetN == "target3" ]]; then SRC_PATH="${WORKSPACE}/crw-theia/dockerfiles/theia-endpoint-runtime-binary"; fi
            # rsync files in github to dist-git
            SYNC_FILES="''' + SYNC_FILES + '''"
            for d in ${SYNC_FILES}; do
              if [[ -f ${SRC_PATH}/${d} ]]; then
                rsync -zrlt ${SRC_PATH}/${d} ${WORKSPACE}/${targetN}/${d}
              elif [[ -d ${SRC_PATH}/${d} ]]; then
                # copy over the files
                rsync -zrlt ${SRC_PATH}/${d}/* ${WORKSPACE}/${targetN}/${d}/
                # sync the directory and delete from target if deleted from source
                rsync -zrlt --delete ${SRC_PATH}/${d}/ ${WORKSPACE}/${targetN}/${d}/
              fi
            done

            # apply changes from upstream Dockerfile to downstream Dockerfile
            find ${SRC_PATH} -name "*ockerfile*" || true
            SOURCEDOCKERFILE="${SRC_PATH}/Dockerfile"
            TARGETDOCKERFILE=""
            if [[ \$targetN == "target1" ]]; then TARGETDOCKERFILE="${WORKSPACE}/target1/Dockerfile"; QUAY_PROJECT="''' + QUAY_PROJECT1 + '''"; fi
            if [[ \$targetN == "target2" ]]; then TARGETDOCKERFILE="${WORKSPACE}/target2/Dockerfile"; QUAY_PROJECT="''' + QUAY_PROJECT2 + '''"; fi
            if [[ \$targetN == "target3" ]]; then TARGETDOCKERFILE="${WORKSPACE}/target3/Dockerfile"; QUAY_PROJECT="''' + QUAY_PROJECT3 + '''"; fi

            # apply generic patches to convert source -> target dockerfile (for use in Brew)
            if [[ ${SOURCEDOCKERFILE} != "" ]] && [[ -f ${SOURCEDOCKERFILE} ]] && [[ ${TARGETDOCKERFILE} != "" ]]; then
              sed ${SOURCEDOCKERFILE} -r \
              `# cannot resolve RHCC from inside Brew so use no registry to resolve from Brew using same container name` \
              -e "s#FROM registry.redhat.io/#FROM #g" \
              -e "s#FROM registry.access.redhat.com/#FROM #g" \
              `# cannot resolve quay from inside Brew so use internal mirror w/ revised container name` \
              -e "s#quay.io/crw/#registry-proxy.engineering.redhat.com/rh-osbs/codeready-workspaces-#g" \
              `# cannot resolve theia-rhel8:next, theia-dev-rhel8:next from inside Brew so use revised container tag` \
              -e "s#(theia-.+):next#\\1:''' + CRW_VERSION + '''#g" \
              > ${TARGETDOCKERFILE}
            else
              echo "[WARNING] ${SOURCEDOCKERFILE} does not exist, so cannot sync to ${TARGETDOCKERFILE}"
            fi

            # add special patches to convert theia bootstrap build into brew-compatible one
            # TODO should this be in build.sh instead?
            if [[ \$targetN == "target2" ]] && [[ ${TARGETDOCKERFILE} != "" ]]; then
              sed -r \
              `# fix up theia loader patch inclusion (3 steps)` \
              -e "s#ADD branding/loader/loader.patch .+#COPY asset-branding.tar.gz /tmp/asset-branding.tar.gz#g" \
              -e "s#ADD (branding/loader/CodeReady_icon_loader.svg .+)#RUN tar xvzf /tmp/asset-branding.tar.gz -C /tmp; cp /tmp/\\1#g" \
              -e "s#(RUN cd .+/theia-source-code && git apply).+#\\1 /tmp/branding/loader/loader.patch#g" \
              `# don't create tarballs` \
              -e "s#.+tar zcf.+##g" \
              `# don't do node-gyp installs, etc.` \
              -e "s#.+node-gyp.+##g" \
              `# copy from builder` \
              -e "s#^COPY branding #COPY --from=builder /tmp/branding #g" \
              -i ${TARGETDOCKERFILE}
            fi

            # update platforms in container.yaml
            platforms=$(for a in `ls $SRC_PATH/asset-list-*.txt` ; do echo $(basename $a .txt | sed -E s/asset-list-//g); done)
            cd ${WORKSPACE}/${targetN}
            ''' + yq_bin + ''' -iy '.platforms.only |= ([])' container.yaml
            for platform in $platforms ; do
              ''' + yq_bin + ''' -iy '.platforms.only |= (.+ ["'$platform'"] | unique)' container.yaml
            done
          done
        ''')

        println("Push changes to dist-git and updateBaseImages")
        sh('''#!/bin/bash -xe
          for targetN in target1 target2 target3; do
            SYNC_FILES="''' + SYNC_FILES + '''"
            cd ${WORKSPACE}/${targetN}
            if [[ \$(git diff --name-only) ]]; then # file changed
              export KRB5CCNAME=/var/tmp/crw-build_ccache
              for f in ${SYNC_FILES}; do
                if [[ -f $f ]] || [[ -d $f ]]; then
                  git add $f
                else
                  echo "[WARNING] File or folder ${WORKSPACE}/${targetN}/$f does not exist. Skipping!"
                fi
              done
              git add Dockerfile
              git add container.yaml
              git commit -s -m "[sync] Update from ''' + MIDSTM_REPO + ''' @ ''' + SRC_SHA1[0..7] + '''"
              git push origin ''' + DWNSTM_BRANCH + '''
            fi
          done
          ''')
        util.updateBaseImages("${WORKSPACE}/target1", DWNSTM_BRANCH, "-q")
        util.updateBaseImages("${WORKSPACE}/target2", DWNSTM_BRANCH, "-q")
        util.updateBaseImages("${WORKSPACE}/target3", DWNSTM_BRANCH, "-q")
      } // with credentials

      NEW_SHA1 = util.getLastCommitSHA("${WORKSPACE}/target1")
      NEW_SHA2 = util.getLastCommitSHA("${WORKSPACE}/target2")
      NEW_SHA3 = util.getLastCommitSHA("${WORKSPACE}/target3")
      println "Got NEW_SHA1 in target1 folder: " + NEW_SHA1
      println "Got NEW_SHA2 in target1 folder: " + NEW_SHA2
      println "Got NEW_SHA3 in target1 folder: " + NEW_SHA3
      if (NEW_SHA1.equals(OLD_SHA1) && NEW_SHA2.equals(OLD_SHA2) && NEW_SHA3.equals(OLD_SHA3)) {
        currentBuild.result='UNSTABLE'
      }
    } // wrap
  } // stage
  } // node
} // timeout

timeout(360) {
  node("${buildNode}"){
    stage "rhpkg container-builds"
	  wrap([$class: 'TimestamperBuildWrapper']) {

    def CRW_VERSION = sh(script: '''#!/bin/bash -xe
    wget -qO- https://raw.githubusercontent.com/redhat-developer/codeready-workspaces/''' + DWNSTM_BRANCH + '''/dependencies/VERSION
    ''', returnStdout: true)
    println "Got CRW_VERSION = '" + CRW_VERSION.trim() + "'"

    echo "currentBuild.result = " + currentBuild.result
    if (!currentBuild.result.equals("ABORTED") && !currentBuild.result.equals("FAILED")) {

        def QUAY_REPO_PATHs=(env.ghprbPullId && env.ghprbPullId?.trim()?"":("${SCRATCH}"=="true"?"":"theia-dev-rhel8"))
        echo "[INFO] Trigger get-sources-rhpkg-container-build " + (env.ghprbPullId && env.ghprbPullId?.trim()?"for PR-${ghprbPullId} ":"") + \
        "with SCRATCH = ${SCRATCH}, QUAY_REPO_PATHs = ${QUAY_REPO_PATHs}, JOB_BRANCH = ${CRW_VERSION}"

        // trigger OSBS build
        build(
          job: 'get-sources-rhpkg-container-build',
          wait: true,
          propagate: true,
          parameters: [
            [
              $class: 'StringParameterValue',
              name: 'GIT_PATHs',
              value: "containers/codeready-workspaces-theia-dev",
            ],
            [
              $class: 'StringParameterValue',
              name: 'DWNSTM_BRANCH',
              value: "${DWNSTM_BRANCH}",
            ],
            [
              $class: 'StringParameterValue',
              name: 'QUAY_REPO_PATHs',
              value: "${QUAY_REPO_PATHs}",
            ],
            [
              $class: 'StringParameterValue',
              name: 'SCRATCH',
              value: "${SCRATCH}",
            ],
            [
              $class: 'StringParameterValue',
              name: 'JOB_BRANCH',
              value: "${CRW_VERSION}",
            ]
          ]
        )

        QUAY_REPO_PATHs=(env.ghprbPullId && env.ghprbPullId?.trim()?"":("${SCRATCH}"=="true"?"":"theia-rhel8"))
        echo "[INFO] Trigger get-sources-rhpkg-container-build " + (env.ghprbPullId && env.ghprbPullId?.trim()?"for PR-${ghprbPullId} ":"") + \
        "with SCRATCH = ${SCRATCH}, QUAY_REPO_PATHs = ${QUAY_REPO_PATHs}, JOB_BRANCH = ${CRW_VERSION}"

        // trigger OSBS build
        build(
          job: 'get-sources-rhpkg-container-build',
          wait: true,
          propagate: true,
          parameters: [
            [
              $class: 'StringParameterValue',
              name: 'GIT_PATHs',
              value: "containers/codeready-workspaces-theia",
            ],
            [
              $class: 'StringParameterValue',
              name: 'DWNSTM_BRANCH',
              value: "${DWNSTM_BRANCH}",
            ],
            [
              $class: 'StringParameterValue',
              name: 'QUAY_REPO_PATHs',
              value: "${QUAY_REPO_PATHs}",
            ],
            [
              $class: 'StringParameterValue',
              name: 'SCRATCH',
              value: "${SCRATCH}",
            ],
            [
              $class: 'StringParameterValue',
              name: 'JOB_BRANCH',
              value: "${CRW_VERSION}",
            ]
          ]
        )

        QUAY_REPO_PATHs=(env.ghprbPullId && env.ghprbPullId?.trim()?"":("${SCRATCH}"=="true"?"":"theia-endpoint-rhel8"))
        echo "[INFO] Trigger get-sources-rhpkg-container-build " + (env.ghprbPullId && env.ghprbPullId?.trim()?"for PR-${ghprbPullId} ":"") + \
        "with SCRATCH = ${SCRATCH}, QUAY_REPO_PATHs = ${QUAY_REPO_PATHs}, JOB_BRANCH = ${CRW_VERSION}"

        // trigger OSBS build
        build(
          job: 'get-sources-rhpkg-container-build',
          wait: true,
          propagate: true,
          parameters: [
            [
              $class: 'StringParameterValue',
              name: 'GIT_PATHs',
              value: "containers/codeready-workspaces-theia-endpoint",
            ],
            [
              $class: 'StringParameterValue',
              name: 'DWNSTM_BRANCH',
              value: "${DWNSTM_BRANCH}",
            ],
            [
              $class: 'StringParameterValue',
              name: 'QUAY_REPO_PATHs',
              value: "${QUAY_REPO_PATHs}",
            ],
            [
              $class: 'StringParameterValue',
              name: 'SCRATCH',
              value: "${SCRATCH}",
            ],
            [
              $class: 'StringParameterValue',
              name: 'JOB_BRANCH',
              value: "${CRW_VERSION}",
            ]
          ]
        )
    } else {
      echo "[ERROR] Build status is " + currentBuild.result + " from previous stage. Skip!"
    }
   }
  }
}
