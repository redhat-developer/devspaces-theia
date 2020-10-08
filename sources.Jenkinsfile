#!/usr/bin/env groovy

import groovy.transform.Field

// PARAMETERS for this pipeline:
// SCRATCH = true (don't push to Quay) or false (do push to Quay)

@Field String CHE_THEIA_BRANCH = "7.19.x" // che-theia branch to build
@Field String MIDSTM_BRANCH = "crw-2.5-rhel-8" // branch in GH repo, eg., crw-2.5-rhel-8

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

def installSkopeo(String CRW_VERSION)
{
sh '''#!/bin/bash -xe
pushd /tmp >/dev/null
# remove any older versions
sudo yum remove -y skopeo || true
# install from @kcrane build
if [[ ! -x /usr/local/bin/skopeo ]]; then
    # note, need -k for insecure connection or ppc64le node dies
    sudo curl -ksSLO "https://codeready-workspaces-jenkins.rhev-ci-vms.eng.rdu2.redhat.com/job/crw-deprecated_''' + CRW_VERSION + '''/lastSuccessfulBuild/artifact/codeready-workspaces-deprecated/skopeo/target/skopeo-$(uname -m).tar.gz"
fi
if [[ -f /tmp/skopeo-$(uname -m).tar.gz ]]; then
    sudo tar xzf /tmp/skopeo-$(uname -m).tar.gz --overwrite -C /usr/local/bin/
    sudo chmod 755 /usr/local/bin/skopeo
    sudo rm -f /tmp/skopeo-$(uname -m).tar.gz
fi
popd >/dev/null
skopeo --version
'''
}

// Nodes to run artifact build on ex. ['rhel7-releng', 's390x-rhel7-beaker', 'ppc64le-rhel7-beaker']
def List build_nodes = ['rhel7-releng', 's390x-rhel7-beaker', 'ppc64le-rhel7-beaker']
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
curl -sSLo- https://raw.githubusercontent.com/nvm-sh/nvm/${LATEST_NVM}/install.sh | bash
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
              installSkopeo(CRW_VERSION)

              def buildLog = ""
              sh '''#!/bin/bash -x
    # REQUIRE: skopeo
    curl -ssL https://raw.githubusercontent.com/redhat-developer/codeready-workspaces/''' + MIDSTM_BRANCH + '''/product/updateBaseImages.sh -o /tmp/updateBaseImages.sh
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
