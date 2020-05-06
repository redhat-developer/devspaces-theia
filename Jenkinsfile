#!/usr/bin/env groovy

// PARAMETERS for this pipeline:
// branchToBuildCRW = codeready-workspaces branch to build: */2.0.x or */master
// THEIA_BRANCH = theia branch/tag to build: master, 8814c20, v0.12.0
// CHE_THEIA_BRANCH = che-theia branch to build: master, 7.9.x
// GITHUB_TOKEN = (github token)
// USE_PUBLIC_NEXUS = true or false (if true, don't use https://repository.engineering.redhat.com/nexus/repository/registry.npmjs.org)
// SCRATCH = true (don't push to Quay) or false (do push to Quay)

def buildNode = "rhel7-releng" // slave label
def installNPM(){
    def yarnVersion="1.17.3"
    def nodeHome = tool 'nodejs-10.19.0'
    env.PATH="${nodeHome}/bin:${env.PATH}"
    sh "echo USE_PUBLIC_NEXUS = ${USE_PUBLIC_NEXUS}"
    if ("${USE_PUBLIC_NEXUS}".equals("false")) {
        sh '''#!/bin/bash -xe

echo '
registry=https://repository.engineering.redhat.com/nexus/repository/registry.npmjs.org/
cafile=/etc/pki/ca-trust/source/anchors/RH-IT-Root-CA.crt
strict-ssl=false
virtual/:_authToken=credentials
always-auth=true
' > ${HOME}/.npmrc

echo '
# registry "https://repository.engineering.redhat.com/nexus/repository/registry.npmjs.org/"
registry "https://registry.yarnpkg.com"
cafile /etc/pki/ca-trust/source/anchors/RH-IT-Root-CA.crt
strict-ssl false
' > ${HOME}/.yarnrc

cat ${HOME}/.npmrc
cat ${HOME}/.yarnrc

npm install --global yarn@''' + yarnVersion + '''
npm config get; yarn config get list
npm --version; yarn --version
'''
    }
    else
    {
        sh '''#!/bin/bash -xe
rm -f ${HOME}/.npmrc ${HOME}/.yarnrc
npm install --global yarn@''' + yarnVersion + '''
npm --version; yarn --version
'''
    }
}

timeout(20) {
    node("${buildNode}"){
        // check out che-theia before we need it in build.sh so we can use it as a poll basis
        // then discard this folder as we need to check them out and massage them for crw
        stage "Checkout Che Theia"
        sh "mkdir -p tmp"
        checkout([$class: 'GitSCM', 
          branches: [[name: "${CHE_THEIA_BRANCH}"]], 
          doGenerateSubmoduleConfigurations: false, 
          poll: true,
          extensions: [
            [$class: 'RelativeTargetDirectory', relativeTargetDir: "tmp/che-theia"]
            // , 
            // [$class: 'CloneOption', shallow: true, depth: 1]
          ], 
          submoduleCfg: [], 
          userRemoteConfigs: [[url: "https://github.com/eclipse/che-theia.git"]]])
        sh "rm -fr tmp"
    }
}
timeout(180) {
    node("${buildNode}"){
        stage "Build CRW Theia --no-async-tests"
        cleanWs()
        checkout([$class: 'GitSCM', 
          branches: [[name: "${branchToBuildCRW}"]], 
          doGenerateSubmoduleConfigurations: false, 
          poll: true,
          extensions: [[$class: 'RelativeTargetDirectory', relativeTargetDir: "crw-theia"]], 
          submoduleCfg: [], 
          userRemoteConfigs: [[url: "https://github.com/redhat-developer/codeready-workspaces-theia.git"]]])
        installNPM()

        def buildLog = ""

        // CRW-360 use RH NPM mirror
        // if ("${USE_PUBLIC_NEXUS}".equals("false")) {
        //     sh '''#!/bin/bash -xe 
        //     for d in $(find . -name yarn.lock -o -name package.json); do 
        //         sed -i $d 's|https://registry.yarnpkg.com/|https://repository.engineering.redhat.com/nexus/repository/registry.npmjs.org/|g'
        //     '''
        // }

        // increase verbosity of yarn calls to we can log what's being downloaded from 3rd parties - doesn't work at this stage; must move into build.sh
        // sh '''#!/bin/bash -xe 
        // for d in $(find . -name package.json); do sed -i $d -e 's#yarn #yarn --verbose #g'; done
        // '''

        // TODO pass che-theia and theia tags/branches to this script
        // "--squash" is only supported on a Docker daemon with experimental features enabled
        def BUILD_PARAMS="--ctb ${CHE_THEIA_BRANCH} --tb ${THEIA_BRANCH} --tgr ${THEIA_GITHUB_REPO} -d -t -b --no-cache --rmi:all --no-async-tests"
        def buildStatusCode = 0
        ansiColor('xterm') {
            buildStatusCode = sh script:'''#!/bin/bash -xe
export GITHUB_TOKEN="''' + GITHUB_TOKEN + '''"
mkdir -p ${WORKSPACE}/logs/
pushd ${WORKSPACE}/crw-theia >/dev/null
    ./build.sh ''' + BUILD_PARAMS + ''' 2>&1 | tee ${WORKSPACE}/logs/crw-theia_buildlog.txt
popd >/dev/null
''', returnStatus: true

            buildLog = readFile("${WORKSPACE}/logs/crw-theia_buildlog.txt").trim()
            if (buildStatusCode != 0 || buildLog.find(/returned a non-zero code:/)?.trim())
            {
              ansiColor('xterm') {
                echo ""
                echo "=============================================================================================="
                echo ""
                error "[ERROR] Build has failed with exit code " + buildStatusCode + "\n\n" + buildLog
              }
              currentBuild.result = 'FAILED'
            }

            stash name: 'stashDockerfilesToSync', includes: findFiles(glob: 'crw-theia/dockerfiles/**').join(", ")

            archiveArtifacts fingerprint: true, onlyIfSuccessful: true, allowEmptyArchive: false, artifacts: "crw-theia/dockerfiles/**, logs/*"

            // TODO start collecting shas with "git rev-parse --short=4 HEAD"
            def descriptString="Build #${BUILD_NUMBER} (${BUILD_TIMESTAMP}) <br/> :: crw-theia @ ${branchToBuildCRW}, che-theia @ ${CHE_THEIA_BRANCH}, theia @ ${THEIA_BRANCH}"
            echo "${descriptString}"
            currentBuild.description="${descriptString}"

            writeFile(file: 'project.rules', text:
'''
# warnings/errors to ignore
ok /Couldn't create directory: Failure/
ok /warning .+ The engine "theiaPlugin" appears to be invalid./
ok /warning .+ The engine "vscode" appears to be invalid./

# section starts: these are used to group errors and warnings found after the line; also creates a quick access link.
start /====== handle_.+/

# warnings
warning /.+\\[WARNING\\].+/
warning /[Ww]arning/
warning /WARNING/
warning /Connection refused/

# errors
error / \\[ERROR\\] /
error /exec returned: .+/
error /non-zero code/
error /ripgrep: Command failed/
error /The following error occurred/
error /Downloading ripgrep failed/
error /API rate limit exceeded/
error /error exit delayed from previous errors/
error /tar: .+: No such file or directory/
error /syntax error/
error /fatal: Remote branch/
error /not found: manifest unknown/
error /no space left on device/

# match line starting with 'error ', case-insensitive
error /(?i)^error /
''')
            try 
            {
                step([$class: 'LogParserPublisher',
                failBuildOnError: true,
                unstableOnWarning: false,
                projectRulePath: 'project.rules',
                useProjectRule: true])
            }
            catch (all)
            {
                print "ERROR: LogParserPublisher failed: \n" +al
            }

            buildLog = readFile("${WORKSPACE}/logs/crw-theia_buildlog.txt").trim()
            if (buildStatusCode != 0 || buildLog.find(/Command failed|exit code/)?.trim())
            {
                error "[ERROR] Build has failed with exit code " + buildStatusCode + "\n\n" + buildLog
                currentBuild.result = 'FAILED'
            }
        }
    }
}

def SOURCE_BRANCH = "master"
def SOURCE_REPO = "redhat-developer/codeready-workspaces-theia" //source repo from which to find and sync commits to pkgs.devel repo 
def GIT_PATH1 = "containers/codeready-workspaces-theia-dev" // dist-git repo to use as target
def GIT_PATH2 = "containers/codeready-workspaces-theia" // dist-git repo to use as target
def GIT_PATH3 = "containers/codeready-workspaces-theia-endpoint" // dist-git repo to use as target

def GIT_BRANCH = "crw-2.2-rhel-8" // target branch in dist-git repo, eg., crw-2.2-rhel-8
def QUAY_PROJECT1 = "theia-dev" // also used for the Brew dockerfile params
def QUAY_PROJECT2 = "theia" // also used for the Brew dockerfile params
def QUAY_PROJECT3 = "theia-endpoint" // also used for the Brew dockerfile params

def OLD_SHA1=""
def OLD_SHA2=""
def OLD_SHA3=""
def SRC_SHA1=""

timeout(120) {
  node("${buildNode}"){ stage "Sync repos"

    echo "currentBuild.result" + currentBuild.result
    if (!currentBuild.result.equals("ABORTED") && !currentBuild.result.equals("FAILED")) {

    withCredentials([string(credentialsId:'devstudio-release.token', variable: 'GITHUB_TOKEN'), 
        file(credentialsId: 'crw-build.keytab', variable: 'CRW_KEYTAB')]) {
        checkout([$class: 'GitSCM', 
            branches: [[name: "${branchToBuildCRW}"]], 
            doGenerateSubmoduleConfigurations: false, 
            poll: true,
            extensions: [[$class: 'RelativeTargetDirectory', relativeTargetDir: "crw-theia"]], 
            submoduleCfg: [], 
            userRemoteConfigs: [[url: "https://github.com/redhat-developer/codeready-workspaces-theia.git"]]])
        // retrieve files in crw-theia/dockerfiles/theia-dev, crw-theia/dockerfiles/theia, crw-theia/dockerfiles/theia-endpoint-runtime-binary
        unstash 'stashDockerfilesToSync' 

           def BOOTSTRAP = '''#!/bin/bash -xe

# bootstrapping: if keytab is lost, upload to 
# https://codeready-workspaces-jenkins.rhev-ci-vms.eng.rdu2.redhat.com/credentials/store/system/domain/_/
# then set Use secret text above and set Bindings > Variable (path to the file) as ''' + CRW_KEYTAB + '''
chmod 700 ''' + CRW_KEYTAB + ''' && chown ''' + USER + ''' ''' + CRW_KEYTAB + '''
# create .k5login file
echo "crw-build/codeready-workspaces-jenkins.rhev-ci-vms.eng.rdu2.redhat.com@REDHAT.COM" > ~/.k5login
chmod 644 ~/.k5login && chown ''' + USER + ''' ~/.k5login
 echo "pkgs.devel.redhat.com,10.19.208.80 ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAplqWKs26qsoaTxvWn3DFcdbiBxqRLhFngGiMYhbudnAj4li9/VwAJqLm1M6YfjOoJrj9dlmuXhNzkSzvyoQODaRgsjCG5FaRjuN8CSM/y+glgCYsWX1HFZSnAasLDuW0ifNLPR2RBkmWx61QKq+TxFDjASBbBywtupJcCsA5ktkjLILS+1eWndPJeSUJiOtzhoN8KIigkYveHSetnxauxv1abqwQTk5PmxRgRt20kZEFSRqZOJUlcl85sZYzNC/G7mneptJtHlcNrPgImuOdus5CW+7W49Z/1xqqWI/iRjwipgEMGusPMlSzdxDX4JzIx6R53pDpAwSAQVGDz4F9eQ==
" >> ~/.ssh/known_hosts

ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts

# see https://mojo.redhat.com/docs/DOC-1071739
if [[ -f ~/.ssh/config ]]; then mv -f ~/.ssh/config{,.BAK}; fi
echo "
GSSAPIAuthentication yes
GSSAPIDelegateCredentials yes

Host pkgs.devel.redhat.com
User crw-build/codeready-workspaces-jenkins.rhev-ci-vms.eng.rdu2.redhat.com@REDHAT.COM
" > ~/.ssh/config
chmod 600 ~/.ssh/config

# initialize kerberos
export KRB5CCNAME=/var/tmp/crw-build_ccache
kinit "crw-build/codeready-workspaces-jenkins.rhev-ci-vms.eng.rdu2.redhat.com@REDHAT.COM" -kt ''' + CRW_KEYTAB + '''
klist # verify working

hasChanged=0

# REQUIRE: skopeo
curl -L -s -S https://raw.githubusercontent.com/redhat-developer/codeready-workspaces/master/product/updateBaseImages.sh -o /tmp/updateBaseImages.sh
chmod +x /tmp/updateBaseImages.sh 
cd ${WORKSPACE}/crw-theia
  git checkout --track origin/''' + branchToBuildCRW + ''' || true
  export GITHUB_TOKEN=''' + GITHUB_TOKEN + ''' # echo "''' + GITHUB_TOKEN + '''"
  git config user.email "nickboldt+devstudio-release@gmail.com"
  git config user.name "Red Hat Devstudio Release Bot"
  git config --global push.default matching
  OLD_SHA=\$(git rev-parse HEAD) # echo ${OLD_SHA:0:8}

  # TODO later we can enable updating the sources in crw-theia repo via this step, but would also need to check our sources again and work in 
  #/tmp/updateBaseImages.sh -b ''' + branchToBuildCRW + ''' -w ${WORKSPACE}/crw-theia/conf -f builder-image-from.dockerfile
  #/tmp/updateBaseImages.sh -b ''' + branchToBuildCRW + ''' -w ${WORKSPACE}/crw-theia/conf -f runtime-from.dockerfile
  #/tmp/updateBaseImages.sh -b ''' + branchToBuildCRW + ''' -w ${WORKSPACE}/crw-theia -f Dockerfile
  #NEW_SHA=\$(git rev-parse HEAD) # echo ${NEW_SHA:0:8}
  #if [[ "${OLD_SHA}" != "${NEW_SHA}" ]]; then hasChanged=1; fi
cd ..
for targetN in target1 target2 target3; do
    # fetch sources to be updated
    if [[ \$targetN == "target1" ]]; then GIT_PATH="''' + GIT_PATH1 + '''"; fi
    if [[ \$targetN == "target2" ]]; then GIT_PATH="''' + GIT_PATH2 + '''"; fi
    if [[ \$targetN == "target3" ]]; then GIT_PATH="''' + GIT_PATH3 + '''"; fi
    if [[ ! -d ${WORKSPACE}/${targetN} ]]; then git clone ssh://crw-build@pkgs.devel.redhat.com/${GIT_PATH} ${targetN}; fi
    cd ${WORKSPACE}/${targetN}
    git checkout --track origin/''' + GIT_BRANCH + ''' || true
    git config user.email crw-build@REDHAT.COM
    git config user.name "CRW Build"
    git config --global push.default matching
    cd ..
done
'''
      sh BOOTSTRAP

      SRC_SHA1 = sh(script: '''#!/bin/bash -xe
      cd ${WORKSPACE}/crw-theia; git rev-parse HEAD
      ''', returnStdout: true)
      println "Got SRC_SHA1 in sources folder: " + SRC_SHA1

      OLD_SHA1 = sh(script: '''#!/bin/bash -xe
      cd ${WORKSPACE}/target1; git rev-parse HEAD
      ''', returnStdout: true)
      println "Got OLD_SHA1 in target1 folder: " + OLD_SHA1

      OLD_SHA2 = sh(script: '''#!/bin/bash -xe
      cd ${WORKSPACE}/target2; git rev-parse HEAD
      ''', returnStdout: true)
      println "Got OLD_SHA2 in target2 folder: " + OLD_SHA2

      OLD_SHA3 = sh(script: '''#!/bin/bash -xe
      cd ${WORKSPACE}/target3; git rev-parse HEAD
      ''', returnStdout: true)
      println "Got OLD_SHA3 in target3 folder: " + OLD_SHA3

      // TODO should this be a branch instead of just master?
      CRW_VERSION = sh(script: '''#!/bin/bash -xe
      wget -qO- https://raw.githubusercontent.com/redhat-developer/codeready-workspaces/master/dependencies/VERSION
      ''', returnStdout: true)
      println "Got CRW_VERSION = '" + CRW_VERSION.trim() + "'"

           sh BOOTSTRAP + '''
for targetN in target1 target2 target3; do
    if [[ \$targetN == "target1" ]]; then SRC_PATH="${WORKSPACE}/crw-theia/dockerfiles/''' + QUAY_PROJECT1 + '''"; fi
    if [[ \$targetN == "target2" ]]; then SRC_PATH="${WORKSPACE}/crw-theia/dockerfiles/''' + QUAY_PROJECT2 + '''"; fi
    # special case since folder created != quay image
    if [[ \$targetN == "target3" ]]; then SRC_PATH="${WORKSPACE}/crw-theia/dockerfiles/theia-endpoint-runtime-binary"; fi
    # rsync files in github to dist-git
    SYNC_FILES="src etc"
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
        -e "s#(theia-.+):next#\\1:''' + CRW_VERSION.trim() + '''#g" \
        > ${TARGETDOCKERFILE}
    else
        echo "[WARNING] ${SOURCEDOCKERFILE} does not exist, so cannot sync to ${TARGETDOCKERFILE}"
    fi

    # add special patches to convert theia bootstrap build into brew-compatible one
    # TODO should this be in build.sh instead?
    if [[ \$targetN == "target2" ]] && [[ ${TARGETDOCKERFILE} != "" ]]; then
      sed -r \
        `# fix up theia loader patch inclusion (3 steps)` \
        -e "s#ADD branding/loader/loader.patch .+#COPY branding.zip /tmp/branding.zip#g" \
        -e "s#ADD (branding/loader/CodeReady_icon_loader.svg .+)#RUN unzip -d /tmp/ /tmp/branding.zip; cp /tmp/\\1#g" \
        -e "s#(RUN cd .+/theia-source-code && git apply).+#\\1 /tmp/branding/loader/loader.patch#g" \
        `# don't create tarballs` \
        -e "s#.+tar zcf.+##g" \
        `# don't do node-gyp installs, etc.` \
        -e "s#.+node-gyp.+##g" \
        `# copy from builder` \
        -e "s#^COPY branding #COPY --from=builder /tmp/branding #g" \
        -i ${TARGETDOCKERFILE}
    fi

    # push changes in github to dist-git
    cd ${WORKSPACE}/${targetN}
    if [[ \$(git diff --name-only) ]]; then # file changed
    OLD_SHA=\$(git rev-parse HEAD) # echo ${OLD_SHA:0:8}
    for f in ${SYNC_FILES}; do 
      if [[ -f $f ]] || [[ -d $f ]]; then 
        git add $f
      else 
        echo "[WARNING] File or folder ${WORKSPACE}/${targetN}/$f does not exist. Skipping!"
      fi
    done
    git add Dockerfile
    git commit -s -m "[sync] Update from ''' + SOURCE_REPO + ''' @ ${SRC_SHA1:0:8}" .
    git push origin ''' + GIT_BRANCH + '''
    NEW_SHA=\$(git rev-parse HEAD) # echo ${NEW_SHA:0:8}
    if [[ "${OLD_SHA}" != "${NEW_SHA}" ]]; then hasChanged=1; fi
    echo "[sync] Updated pkgs.devel @ ${NEW_SHA:0:8} from ''' + SOURCE_REPO + ''' @ ${SRC_SHA1:0:8}"
    fi
    cd ..

    # update base image
    cd ${WORKSPACE}/${targetN}
    OLD_SHA=\$(git rev-parse HEAD) # echo ${OLD_SHA:0:8}
    /tmp/updateBaseImages.sh -b ''' + GIT_BRANCH + ''' -w ${TARGETDOCKERFILE%/*} -f ${TARGETDOCKERFILE##*/}
    NEW_SHA=\$(git rev-parse HEAD) # echo ${NEW_SHA:0:8}
    if [[ "${OLD_SHA}" != "${NEW_SHA}" ]]; then hasChanged=1; fi
    cd ..
done
          '''
    }

      def NEW_SHA1 = sh(script: '''#!/bin/bash -xe
      cd ${WORKSPACE}/target1; git rev-parse HEAD
      ''', returnStdout: true)
      println "Got NEW_SHA1 in target1 folder: " + NEW_SHA1

      def NEW_SHA2 = sh(script: '''#!/bin/bash -xe
      cd ${WORKSPACE}/target2; git rev-parse HEAD
      ''', returnStdout: true)
      println "Got NEW_SHA2 in target2 folder: " + NEW_SHA2

      def NEW_SHA3 = sh(script: '''#!/bin/bash -xe
      cd ${WORKSPACE}/target3; git rev-parse HEAD
      ''', returnStdout: true)
      println "Got NEW_SHA3 in target3 folder: " + NEW_SHA3

      if (NEW_SHA1.equals(OLD_SHA1) && NEW_SHA2.equals(OLD_SHA2) && NEW_SHA3.equals(OLD_SHA3)) {
        currentBuild.result='UNSTABLE'
      }
    } else {
      echo "[ERROR] Build status is " + currentBuild.result + " from previous stage. Skip!"
    }
  }
}

timeout(180) {
  node("${buildNode}"){
    stage "rhpkg container-builds"

    echo "currentBuild.result" + currentBuild.result
    if (!currentBuild.result.equals("ABORTED") && !currentBuild.result.equals("FAILED")) {

        def QUAY_REPO_PATHs=(env.ghprbPullId && env.ghprbPullId?.trim()?"":("${SCRATCH}"=="true"?"":"theia-dev-rhel8"))

        def matcher = ( "${JOB_NAME}" =~ /.*_(stable-branch|master).*/ )
        def JOB_BRANCH= (matcher.matches() ? matcher[0][1] : "master")

        echo "[INFO] Trigger get-sources-rhpkg-container-build " + (env.ghprbPullId && env.ghprbPullId?.trim()?"for PR-${ghprbPullId} ":"") + \
        "with SCRATCH = ${SCRATCH}, QUAY_REPO_PATHs = ${QUAY_REPO_PATHs}, JOB_BRANCH = ${JOB_BRANCH}"

        // trigger OSBS build
        build(
          job: 'get-sources-rhpkg-container-build',
          wait: false,
          propagate: true,
          parameters: [
            [
              $class: 'StringParameterValue',
              name: 'GIT_PATHs',
              value: "containers/codeready-workspaces-theia-dev",
            ],
            [
              $class: 'StringParameterValue',
              name: 'GIT_BRANCH',
              value: "crw-2.2-rhel-8",
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
              value: "${JOB_BRANCH}",
            ]
          ]
        )

        QUAY_REPO_PATHs=(env.ghprbPullId && env.ghprbPullId?.trim()?"":("${SCRATCH}"=="true"?"":"theia-rhel8"))

        matcher = ( "${JOB_NAME}" =~ /.*_(stable-branch|master).*/ )
        JOB_BRANCH= (matcher.matches() ? matcher[0][1] : "master")

        echo "[INFO] Trigger get-sources-rhpkg-container-build " + (env.ghprbPullId && env.ghprbPullId?.trim()?"for PR-${ghprbPullId} ":"") + \
        "with SCRATCH = ${SCRATCH}, QUAY_REPO_PATHs = ${QUAY_REPO_PATHs}, JOB_BRANCH = ${JOB_BRANCH}"

        // trigger OSBS build
        build(
          job: 'get-sources-rhpkg-container-build',
          wait: false,
          propagate: true,
          parameters: [
            [
              $class: 'StringParameterValue',
              name: 'GIT_PATHs',
              value: "containers/codeready-workspaces-theia",
            ],
            [
              $class: 'StringParameterValue',
              name: 'GIT_BRANCH',
              value: "crw-2.2-rhel-8",
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
              value: "${JOB_BRANCH}",
            ]
          ]
        )

        QUAY_REPO_PATHs=(env.ghprbPullId && env.ghprbPullId?.trim()?"":("${SCRATCH}"=="true"?"":"theia-endpoint-rhel8"))

        matcher = ( "${JOB_NAME}" =~ /.*_(stable-branch|master).*/ )
        JOB_BRANCH= (matcher.matches() ? matcher[0][1] : "master")

        echo "[INFO] Trigger get-sources-rhpkg-container-build " + (env.ghprbPullId && env.ghprbPullId?.trim()?"for PR-${ghprbPullId} ":"") + \
        "with SCRATCH = ${SCRATCH}, QUAY_REPO_PATHs = ${QUAY_REPO_PATHs}, JOB_BRANCH = ${JOB_BRANCH}"

        // trigger OSBS build
        build(
          job: 'get-sources-rhpkg-container-build',
          wait: false,
          propagate: true,
          parameters: [
            [
              $class: 'StringParameterValue',
              name: 'GIT_PATHs',
              value: "containers/codeready-workspaces-theia-endpoint",
            ],
            [
              $class: 'StringParameterValue',
              name: 'GIT_BRANCH',
              value: "crw-2.2-rhel-8",
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
              value: "${JOB_BRANCH}",
            ]
          ]
        )
    } else {
      echo "[ERROR] Build status is " + currentBuild.result + " from previous stage. Skip!"
    }
  }
}