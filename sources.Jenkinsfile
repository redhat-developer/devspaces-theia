#!/usr/bin/env groovy

import groovy.transform.Field

// PARAMETERS for this pipeline:
// CHE_THEIA_BRANCH = che-theia branch to build: master, 7.17.x
// MIDSTM_BRANCH = codeready-workspaces-theia branch to build: crw-2.4-rhel-8
// SCRATCH = true (don't push to Quay) or false (do push to Quay)

// other params not worth setting in Jenkins (they don't change)
def THEIA_BRANCH = "master" // theia branch/tag to build: master (will then compute the correct SHA to use)
def THEIA_GITHUB_REPO = "eclipse-theia/theia" // default: eclipse-theia/theia; optional: redhat-developer/eclipse-theia
def THEIA_COMMIT_SHA = "" // For 7.13+, look at https://github.com/eclipse/che-theia/blob/7.13.x/build.include#L16 (3f28503e754bbb4fa6534612af3d1ed6da3ed66a)
                          // (or leave blank to compute within build.sh)
@Field String USE_PUBLIC_NEXUS = "true" // or false (if true, don't use https://repository.engineering.redhat.com/nexus/repository/registry.npmjs.org)
                              // TODO https://issues.redhat.com/browse/CRW-360 - eventually we should use RH npm mirror

@Field String CRW_VERSION_F = ""

def String getCrwVersion(String MIDSTM_BRANCH) {
  if (CRW_VERSION_F.equals("")) {
    CRW_VERSION_F = sh(script: '''#!/bin/bash -xe
    curl -sSLo- https://raw.githubusercontent.com/redhat-developer/codeready-workspaces/''' + MIDSTM_BRANCH + '''/dependencies/VERSION''', returnStdout: true).trim()
  }
  return CRW_VERSION_F
}
// Nodes to run artifact build on ex. ['rhel7-releng', 's390x-rhel7-beaker', 'ppc64le-rhel7-beaker']
def List build_nodes = NODES.tokenize(",").collect { it.trim() }
def List platforms = [] // populate with architectures we are building artifacts on
def Map tasks = [failFast: false]

// DO NOT CHANGE THIS until a newer version exists in ubi images used to build crw-theia, or build will fail.
def nodeVersion = "12.18.2"
def installNPM(nodeVersion) {
  def yarnVersion="1.17.3"

  sh '''#!/bin/bash -e
export LATEST_NVM="$(git ls-remote --refs --tags https://github.com/nvm-sh/nvm.git \
          | cut --delimiter='/' --fields=3 | tr '-' '~'| sort --version-sort| tail --lines=1)"

export NODE_VERSION=''' + nodeVersion + '''
export METHOD=script
export PROFILE=/dev/null
curl -sS -o- https://raw.githubusercontent.com/nvm-sh/nvm/${LATEST_NVM}/install.sh | bash
'''
  def nodeHome = sh(script: '''#!/bin/bash -e
source $HOME/.nvm/nvm.sh
nvm use --silent ''' + nodeVersion + '''
dirname $(nvm which node)''' , returnStdout: true).trim()
  env.PATH="${nodeHome}:${env.PATH}"
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
node --version; npm --version; yarn --version
'''
  }
}

for (int i=0; i < build_nodes.size(); i++) {
  def String nodeLabel = "${build_nodes[i]}"
  tasks[build_nodes[i]] = { ->
    timeout(20) {
      node(nodeLabel) {
        stage ("Checkout Che Theia on ${nodeLabel}") {
          wrap([$class: 'TimestamperBuildWrapper']) {
            // check out che-theia before we need it in build.sh so we can use it as a poll basis
            // then discard this folder as we need to check them out and massage them for crw
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
      }
    }
    timeout(600) {
      node(nodeLabel) {
        stage ("Build CRW Theia on ${nodeLabel}") {
          wrap([$class: 'TimestamperBuildWrapper']) {
            cleanWs()
            sh "docker system prune -af"
            platforms.add(sh(script: '''uname -m''', returnStdout:true).trim())
            withCredentials([string(credentialsId:'devstudio-release.token', variable: 'GITHUB_TOKEN'),
                file(credentialsId: 'crw-build.keytab', variable: 'CRW_KEYTAB')]) {
              checkout([$class: 'GitSCM',
                  branches: [[name: "${MIDSTM_BRANCH}"]],
                  doGenerateSubmoduleConfigurations: false,
                  poll: true,
                  extensions: [[$class: 'RelativeTargetDirectory', relativeTargetDir: "crw-theia"]],
                  submoduleCfg: [],
                  userRemoteConfigs: [[url: "https://github.com/redhat-developer/codeready-workspaces-theia.git"]]])
              installNPM(nodeVersion)
              CRW_VERSION = getCrwVersion(MIDSTM_BRANCH)
              println "CRW_VERSION = '" + CRW_VERSION + "'"

              def buildLog = ""
              sh '''#!/bin/bash -x
    # REQUIRE: skopeo
    curl -L -s -S https://raw.githubusercontent.com/redhat-developer/codeready-workspaces/''' + MIDSTM_BRANCH + '''/product/updateBaseImages.sh -o /tmp/updateBaseImages.sh
    chmod +x /tmp/updateBaseImages.sh
    cd ${WORKSPACE}/crw-theia
      git checkout --track origin/''' + MIDSTM_BRANCH + ''' || true
      export GITHUB_TOKEN=''' + GITHUB_TOKEN + ''' # echo "''' + GITHUB_TOKEN + '''"
      git config user.email "nickboldt+devstudio-release@gmail.com"
      git config user.name "Red Hat Devstudio Release Bot"
      git config --global push.default matching
      OLD_SHA=\$(git rev-parse HEAD) # echo ${OLD_SHA:0:8}

      # SOLVED :: Fatal: Could not read Username for "https://github.com", No such device or address :: https://github.com/github/hub/issues/1644
      git remote -v
      git config --global hub.protocol https
      git remote set-url origin https://\$GITHUB_TOKEN:x-oauth-basic@github.com/redhat-developer/codeready-workspaces-theia.git
      git remote -v

      # update base images for the *.dockerfile in conf/ folder
      for df in $(find ${WORKSPACE}/crw-theia/conf/ -name "*from*dockerfile"); do
        /tmp/updateBaseImages.sh -b ''' + MIDSTM_BRANCH + ''' -w ${df%/*} -f ${df##*/} -q
      done

      NEW_SHA=\$(git rev-parse HEAD) # echo ${NEW_SHA:0:8}
      #if [[ "${OLD_SHA}" != "${NEW_SHA}" ]]; then hasChanged=1; fi
    cd ..
    '''

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

              // NOTE: "--squash" is only supported on a Docker daemon with experimental features enabled

              def BUILD_PARAMS="--nv ${nodeVersion} --cv ${CRW_VERSION} --ctb ${CHE_THEIA_BRANCH} --tb ${THEIA_BRANCH} --tgr ${THEIA_GITHUB_REPO} -d -t -b --no-cache --rmi:all --no-async-tests"
              if (!THEIA_COMMIT_SHA.equals("")) {
                BUILD_PARAMS=BUILD_PARAMS+" --tcs ${THEIA_COMMIT_SHA}";
              } else {
                THEIA_COMMIT_SHA = sh(script: '''#!/bin/bash -xe
      pushd /tmp >/dev/null || true
      curl -sSLO https://raw.githubusercontent.com/eclipse/che-theia/''' + CHE_THEIA_BRANCH + '''/build.include
      export $(cat build.include | egrep "^THEIA_COMMIT_SHA") && THEIA_COMMIT_SHA=${THEIA_COMMIT_SHA//\\"/}
      popd >/dev/null || true
      echo -n $THEIA_COMMIT_SHA
      ''', returnStdout: true)
                echo "[INFO] Using Eclipse Theia commit SHA THEIA_COMMIT_SHA = ${THEIA_COMMIT_SHA} from ${CHE_THEIA_BRANCH} branch"
              }

              def buildStatusCode = 0
              ansiColor('xterm') {
                  buildStatusCode = sh script:'''#!/bin/bash -xe
    export GITHUB_TOKEN="''' + GITHUB_TOKEN + '''"
    mkdir -p ${WORKSPACE}/logs/
    pushd ${WORKSPACE}/crw-theia >/dev/null
        node --version
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
                def descriptString="Build #${BUILD_NUMBER} (${BUILD_TIMESTAMP}) <br/> :: crw-theia @ ${MIDSTM_BRANCH}, che-theia @ ${CHE_THEIA_BRANCH}, theia @ ${THEIA_COMMIT_SHA} (${THEIA_BRANCH})"
                echo "${descriptString}"
                currentBuild.description="${descriptString}"
                echo "currentBuild.result = " + currentBuild.result

                writeFile(file: 'project.rules', text:
'''
# warnings/errors to ignore
ok /Couldn.+ create directory: Failure/
ok /warning .+ The engine "theiaPlugin" appears to be invalid./
ok /warning .+ The engine "vscode" appears to be invalid./
ok /\\[Warning\\] Disable async tests in .+/
ok /\\[Warning\\] One or more build-args .+ were not consumed/
ok /Error: No such image: .+/

# section starts: these are used to group errors and warnings found after the line; also creates a quick access link.
start /====== handle_.+/
start /Successfully built .+/
start /Successfully tagged .+/
start /Script run successfully:.+/
start /Build of .+ \\[OK\\].+/
start /docker build .+/
start /docker run .+/
start /docker tag .+/
start /Dockerfiles and tarballs generated.+/
start /Step [0-9/]+ : .+/

# warnings
warning /.+\\[WARNING\\].+/
warning /[Ww]arning/
warning /WARNING/
warning /Connection refused/
warning /error Package .+ refers to a non-existing file .+/

# errors
error / \\[ERROR\\] /
error /exec returned: .+/
error /returned a non-zero code/
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

# match line starting with error, case-insensitive
error /(?i)^error /
''')
/*
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
*/

                buildLog = readFile("${WORKSPACE}/logs/crw-theia_buildlog.txt").trim()
                if (buildStatusCode != 0 || buildLog.find(/Command failed|exit code/)?.trim())
                {
                    error "[ERROR] Build has failed with exit code " + buildStatusCode + "\n\n" + buildLog
                    currentBuild.result = 'FAILED'
                }
                echo "currentBuild.result = " + currentBuild.result
              } // ansiColor
            } // with credentials
          } // wrap
        } // stage
      } // node
    } // timeout
  } // tasks
} // for

stage("Builds") {
    parallel(tasks)
}

def String nodeLabel = "${build_nodes[0]}"

def MIDSTM_REPO = "redhat-developer/codeready-workspaces-theia" //source repo from which to find and sync commits to pkgs.devel repo
def DWNSTM_REPO1 = "containers/codeready-workspaces-theia-dev" // dist-git repo to use as target
def DWNSTM_REPO2 = "containers/codeready-workspaces-theia" // dist-git repo to use as target
def DWNSTM_REPO3 = "containers/codeready-workspaces-theia-endpoint" // dist-git repo to use as target

def DWNSTM_BRANCH = MIDSTM_BRANCH // target branch in dist-git repo, eg., crw-2.4-rhel-8
def QUAY_PROJECT1 = "theia-dev" // also used for the Brew dockerfile params
def QUAY_PROJECT2 = "theia" // also used for the Brew dockerfile params
def QUAY_PROJECT3 = "theia-endpoint" // also used for the Brew dockerfile params

def OLD_SHA1=""
def OLD_SHA2=""
def OLD_SHA3=""
def SRC_SHA1=""

timeout(120) {
  node(nodeLabel) {
    stage ("Sync repos on ${nodeLabel}") {
      wrap([$class: 'TimestamperBuildWrapper']) {
        sh('pip install --user yq')
        yq_bin = sh(script: 'python -m site --user-base', returnStdout:true).trim() + '/bin/yq'
        echo "currentBuild.result = " + currentBuild.result
        if (!currentBuild.result.equals("ABORTED") && !currentBuild.result.equals("FAILED")) {

          withCredentials([string(credentialsId:'devstudio-release.token', variable: 'GITHUB_TOKEN'),
              file(credentialsId: 'crw-build.keytab', variable: 'CRW_KEYTAB')]) {
            checkout([$class: 'GitSCM',
                branches: [[name: "${MIDSTM_BRANCH}"]],
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
curl -L -s -S https://raw.githubusercontent.com/redhat-developer/codeready-workspaces/''' + MIDSTM_BRANCH + '''/product/updateBaseImages.sh -o /tmp/updateBaseImages.sh
chmod +x /tmp/updateBaseImages.sh
cd ${WORKSPACE}/crw-theia
  git checkout --track origin/''' + MIDSTM_BRANCH + ''' || true
  export GITHUB_TOKEN=''' + GITHUB_TOKEN + ''' # echo "''' + GITHUB_TOKEN + '''"
  git config user.email "nickboldt+devstudio-release@gmail.com"
  git config user.name "Red Hat Devstudio Release Bot"
  git config --global push.default matching
  OLD_SHA=\$(git rev-parse HEAD) # echo ${OLD_SHA:0:8}
cd ..
for targetN in target1 target2 target3; do
    # fetch sources to be updated
    if [[ \$targetN == "target1" ]]; then DWNSTM_REPO="''' + DWNSTM_REPO1 + '''"; fi
    if [[ \$targetN == "target2" ]]; then DWNSTM_REPO="''' + DWNSTM_REPO2 + '''"; fi
    if [[ \$targetN == "target3" ]]; then DWNSTM_REPO="''' + DWNSTM_REPO3 + '''"; fi
    if [[ ! -d ${WORKSPACE}/${targetN} ]]; then git clone ssh://crw-build@pkgs.devel.redhat.com/${DWNSTM_REPO} ${targetN}; fi
    cd ${WORKSPACE}/${targetN}
    git checkout --track origin/''' + DWNSTM_BRANCH + ''' || true
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

            CRW_VERSION = getCrwVersion(MIDSTM_BRANCH)
            println "CRW_VERSION = '" + CRW_VERSION + "'"
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
    cd ${WORKSPACE}/${targetN}
    for platform in ''' + platforms.join(" ") + ''' ; do
      ''' + yq_bin + ''' -iy '.platforms.only |= (.+ ["'$platform'"] | unique)' container.yaml
    done

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
    git commit -s -m "[sync] Update from ''' + MIDSTM_REPO + ''' @ ${SRC_SHA1:0:8}" .
    git push origin ''' + DWNSTM_BRANCH + '''
    NEW_SHA=\$(git rev-parse HEAD) # echo ${NEW_SHA:0:8}
    if [[ "${OLD_SHA}" != "${NEW_SHA}" ]]; then hasChanged=1; fi
    echo "[sync] Updated pkgs.devel @ ${NEW_SHA:0:8} from ''' + MIDSTM_REPO + ''' @ ${SRC_SHA1:0:8}"
    fi
    cd ..

    # update base image
    cd ${WORKSPACE}/${targetN}
    OLD_SHA=\$(git rev-parse HEAD) # echo ${OLD_SHA:0:8}
    /tmp/updateBaseImages.sh -b ''' + DWNSTM_BRANCH + ''' -w ${TARGETDOCKERFILE%/*} -f ${TARGETDOCKERFILE##*/} -q
    NEW_SHA=\$(git rev-parse HEAD) # echo ${NEW_SHA:0:8}
    if [[ "${OLD_SHA}" != "${NEW_SHA}" ]]; then hasChanged=1; fi
    cd ..
done
'''
          } // with credentials

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
      } // wrap
    } // stage
  } // node
} // timeout

node(nodeLabel) {
  stage ("Build containers on ${nodeLabel}") {
    echo "currentBuild.result = " + currentBuild.result
    if (!currentBuild.result.equals("ABORTED") && !currentBuild.result.equals("FAILED")) {
      CRW_VERSION = getCrwVersion(MIDSTM_BRANCH)
      println "CRW_VERSION = '" + CRW_VERSION + "'"

      build(
            job: 'crw-theia-containers_' + CRW_VERSION,
            wait: false,
            propagate: false,
            parameters: [
              [
                $class: 'StringParameterValue',
                name: 'SCRATCH',
                value: "${SCRATCH}",
              ]
            ]
          )
    } // if
  } // stage
} //node
