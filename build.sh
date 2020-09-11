#!/bin/bash
# Copyright (c) 2019 Red Hat, Inc.
# This program and the accompanying materials are made
# available under the terms of the Eclipse Public License 2.0
# which is available at https://www.eclipse.org/legal/epl-2.0/
#
# SPDX-License-Identifier: EPL-2.0
#
# Contributors:
#   Red Hat, Inc. - initial API and implementation

set -e
set -u
set -x

usage () {
	echo "

You must export a GITHUB_TOKEN to your shell before running this script, or you will be rate-limited by github.

See https://github.com/settings/tokens for more information.

Usage:
  export GITHUB_TOKEN=*your token here*
  $0 --ctb CHE_THEIA_BRANCH [options]

Examples:
  $0 --ctb 7.17.x --all --no-cache --no-tests --rmi:tmp --cb crw-2.4-rhel-8
  $0 --ctb 7.17.x --all --no-cache --no-tests --rmi:tmp --cv 2.4

Options: 
  $0 -d      | build theia-dev
  $0 -t      | build (or rebuild) theia. Note: if theia-dev not already built, must add -d flag too
  $0 -b      | build (or rebuild) theia-endpoint-runtime-binary. Note: if theia-dev not already built, must add -d flag too
  $0 --all   | build 3 projects: theia-dev, theia, theia-endpoint-runtime-binary

Note that steps are run in the order specified, so always start with -d if needed.

Additional flags:

  --cb       | CRW_BRANCH from which to compute version of CRW to put in Dockerfiles
  --cv       | rather than pull from CRW_BRANCH of redhat-developer/codeready-workspaces/dependencies/VERSION file, set a CRW_VERSION 
  --tb       | container build arg THEIA_BRANCH from which to get Eclipse Theia sources, 
             | default: master; probably don't ever need to override this now that code checkout logic relies on master branch + a specific SHA
  --tgr      | container build arg THEIA_GITHUB_REPO from which to get Eclipse Theia sources, 
             | default: eclipse-theia/theia; optional: redhat-developer/eclipse-theia - so we can build from a tag instead of a SHA
  --tcs      | container build arg THEIA_COMMIT_SHA from which commit SHA to get Eclipse Theia sources
             | default: if not set, extract from https://raw.githubusercontent.com/eclipse/che-theia/CHE_THEIA_BRANCH/build.include

Docker + Podman flags:
  --podman      | detect podman and use that instead of docker for building, running, tagging + deleting containers
  --podmanflags | additional flags for podman builds, eg., '--cgroup-manager=cgroupfs --runtime=/usr/bin/crun'
  --squash      | if running docker in experimental mode, squash images; may not work with podman
  --no-cache    | do not use docker/podman cache

Test control flags:
  --no-async-tests | replace test(...async...) with test.skip(...async...) in .ts test files
  --no-sync-tests  | replace test(...)         with test.skip(...) in .ts test files
  --no-tests       | skip both sync and async tests in .ts test files

Cleanup options:

  --rmi:all | delete all generated images when done
  --rmi:tmp | delete only images with :tmp tag when done
"
	exit
}
if [[ $# -lt 1 ]] || [[ -z $GITHUB_TOKEN ]]; then usage; fi

STEPS=""
DELETE_TMP_IMAGES=0
DELETE_ALL_IMAGES=0
SKIP_ASYNC_TESTS=0
SKIP_SYNC_TESTS=0
DOCKERFLAGS="" # eg., --no-cache --squash
PODMAN="" # by default, use docker
PODMANFLAGS="" # optional flags specific to podman build command 
nodeVersion="12.18.2" # version of node to use (aligned to version in ubi base images)

CRW_VERSION="" # must set this via cmdline
MIDSTM_BRANCH="" # must set this via cmdline
CHE_THEIA_BRANCH="master"
THEIA_BRANCH="master"
THEIA_GITHUB_REPO="eclipse-theia/theia" # or redhat-developer/eclipse-theia so we can build from a tag instead of a random commit SHA
THEIA_COMMIT_SHA=""
for key in "$@"; do
  case $key in 
      '--nv') nodeVersion="$2"; shift 2;;
      '--ctb') CHE_THEIA_BRANCH="$2"; shift 2;;
      '--tb') THEIA_BRANCH="$2"; shift 2;;
      '--tgr') THEIA_GITHUB_REPO="$2"; shift 2;;
      '--tcs') THEIA_COMMIT_SHA="$2"; shift 2;;
      '--cb')  MIDSTM_BRANCH="$2"; shift 2;;
      '--cv')  CRW_VERSION="$2"; shift 2;;
      '-d') STEPS="${STEPS} handle_che_theia_dev"; shift 1;;
      '-t') STEPS="${STEPS} handle_che_theia"; shift 1;;
      '-b') STEPS="${STEPS} handle_che_theia_endpoint_runtime_binary"; shift 1;;
      '--all') STEPS="handle_che_theia_dev handle_che_theia handle_che_theia_endpoint_runtime_binary"; shift 1;;
      '--squash') DOCKERFLAGS="${DOCKERFLAGS} $1"; shift 1;;
      '--no-cache') DOCKERFLAGS="${DOCKERFLAGS} $1"; shift 1;;
      '--rmi:tmp') DELETE_TMP_IMAGES=1; shift 1;;
      '--rmi:all') DELETE_ALL_IMAGES=1; shift 1;;
      '--no-async-tests') SKIP_ASYNC_TESTS=1; shift 1;;
      '--no-sync-tests')  SKIP_SYNC_TESTS=1; shift 1;;
      '--no-tests')       SKIP_ASYNC_TESTS=1; SKIP_SYNC_TESTS=1; shift 1;;
      '--podman')         PODMAN=$(which podman 2>/dev/null || true); shift 1;;
      '--podmanflags')    PODMANFLAGS="$2"; shift 2;;
  esac
done

if [[ ! ${CRW_VERSION} ]] && [[ ${MIDSTM_BRANCH} ]]; then
  CRW_VERSION=$(curl -sSLo- https://raw.githubusercontent.com/redhat-developer/codeready-workspaces/${MIDSTM_BRANCH}/dependencies/VERSION)
fi
if [[ ! ${CRW_VERSION} ]]; then 
  echo "Error: must set either --cb crw-2.4-rhel-8 or --cv 2.4 to define the version of CRW Theia to build."
  usage
fi

# to build with podman if present, use --podman flag, else use docker
if [[ ${PODMAN} ]]; then
  DOCKER="${PODMAN} ${PODMANFLAGS}"
  DOCKERRUN="${PODMAN}"
else
  DOCKER="docker"
  DOCKERRUN="docker"
fi

if [[ ! ${THEIA_COMMIT_SHA} ]]; then
  pushd /tmp >/dev/null || true
  curl -sSLO https://raw.githubusercontent.com/eclipse/che-theia/${CHE_THEIA_BRANCH}/build.include
  export $(cat build.include | egrep "^THEIA_COMMIT_SHA") && THEIA_COMMIT_SHA=${THEIA_COMMIT_SHA//\"/}
  popd >/dev/null || true
fi
echo "[INFO] Using Eclipse Theia commit SHA THEIA_COMMIT_SHA = ${THEIA_COMMIT_SHA}"

#need to edit conf/theia/ubi8-brew/builder-from.dockerfile file as well for now
#need to edit conf/theia-endpoint-runtime/ubi8-brew/builder-from.dockerfile file as well for now
CHE_THEIA_DEV_IMAGE_NAME="quay.io/crw/theia-dev-rhel8:next"
CHE_THEIA_IMAGE_NAME="quay.io/crw/theia-rhel8:next"
CHE_THEIA_ENDPOINT_IMAGE_NAME="quay.io/crw/theia-endpoint-rhel8:next"
CHE_THEIA_ENDPOINT_BINARY_IMAGE_NAME="quay.io/crw/theia-endpoint-binary-rhel8:next"

base_dir=$(cd "$(dirname "$0")"; pwd)

# variables
TMP_DIR=${base_dir}/tmp
BREW_DOCKERFILE_ROOT_DIR=${base_dir}/"dockerfiles"
CHE_THEIA_DIR=${TMP_DIR}/che-theia
TMP_THEIA_DEV_BUILDER_IMAGE="che-theia-dev-builder:tmp"
TMP_THEIA_BUILDER_IMAGE="che-theia-builder:tmp"
TMP_THEIA_RUNTIME_IMAGE="che-theia-runtime:tmp"
TMP_THEIA_ENDPOINT_BUILDER_IMAGE="che-theia-endpoint-builder:tmp"
TMP_THEIA_ENDPOINT_BINARY_BUILDER_IMAGE="che-theia-endpoint-binary-builder:tmp"
TMP_CHE_CUSTOM_NODEJS_DEASYNC_IMAGE="che-custom-nodejs-deasync:$nodeVersion"

sed_in_place() {
    SHORT_UNAME=$(uname -s)
  if [ "$(uname)" == "Darwin" ]; then
    sed -i '' "$@"
  elif [ "${SHORT_UNAME:0:5}" == "Linux" ]; then
    sed -i "$@"
  fi
}

if [[ ! -d "${TMP_DIR}" ]]; then
  rm -rf "${TMP_DIR}"
  mkdir -p "${TMP_DIR}"
  if [[ ${CHE_THEIA_BRANCH} == *"@"* ]]; then # if the branch includes an @SHA suffix, use that SHA from the branch
    git clone -b "${CHE_THEIA_BRANCH%%@*}" --single-branch https://github.com/eclipse/che-theia "${TMP_DIR}"/che-theia
    if [[ ! -d "${TMP_DIR}"/che-theia ]]; then echo "[ERR""OR] could not clone https://github.com/eclipse/che-theia from ${CHE_THEIA_BRANCH%%@*} !"; exit 1; fi 
    pushd "${TMP_DIR}"/che-theia >/dev/null
      git reset "${CHE_THEIA_BRANCH##*@}" --hard
      if [[ "$(git --no-pager log --pretty=format:'%Cred%h%Creset' --abbrev-commit -1)" != "${CHE_THEIA_BRANCH##*@}" ]]; then 
        echo "[ERR""OR] could not find SHA ${CHE_THEIA_BRANCH##*@} in branch ${CHE_THEIA_BRANCH%%@*} !"; 
        echo "Latest 10 commits:"
        git --no-pager log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %C(blue)%aE%Creset %Cgreen(%cr)%Creset' --abbrev-commit -10
        echo
        exit 1
      fi
    popd >/dev/null
  else # clone from tag/branch
    git clone -b "${CHE_THEIA_BRANCH}" --single-branch --depth 1 https://github.com/eclipse/che-theia "${TMP_DIR}"/che-theia
    if [[ ! -d "${TMP_DIR}"/che-theia ]]; then echo "[ERR""OR] could not clone https://github.com/eclipse/che-theia from ${CHE_THEIA_BRANCH} !"; exit 1; fi 
  fi

  if [[ ${SKIP_ASYNC_TESTS} -eq 1 ]]; then
    set +e
    set +x
    for d in $(find ${CHE_THEIA_DIR} -type f -name "*.ts" | egrep test); do
      ASYNC_TESTS="$(cat $d | grep "test(" | grep "async () => {")"
      if [[ ${ASYNC_TESTS} ]]; then
        echo "[WARNING] Disable async tests in $d"
        # echo $ASYNC_TESTS
        sed_in_place $d -e "s@test(\(.\+async () => {\)@test.skip(\1@g"
        cat $d | grep "test.skip(" | grep "async () => {"
      fi
    done
    set -e
    set -x
  fi
  if [[ ${SKIP_SYNC_TESTS} -eq 1 ]]; then
    set +e
    set +x
    for d in $(find ${CHE_THEIA_DIR} -type f -name "*.ts" | egrep test); do
      SYNC_TESTS="$(cat $d | grep "test(" | grep -v "async" | grep "() => {")"
      if [[ ${SYNC_TESTS} ]]; then
        echo "[WARNING] Disable sync tests in $d"
        # echo $SYNC_TESTS
        sed_in_place $d -e "s@test(\(.\+() => {\)@test.skip(\1@g"
        cat $d | grep "test.skip(" | grep -v "async" | grep "() => {"
      fi
    done
    set -e
    set -x
  fi

  # apply patches against che-theia sources
  pushd "${CHE_THEIA_DIR}" >/dev/null
    # TODO add some patches into ./patches/ and apply them here
  popd >/dev/null

  # init yarn in che-theia
  pushd "${CHE_THEIA_DIR}" >/dev/null
  CHE_THEIA_SHA=$(git rev-parse --short=4 HEAD); echo "CHE_THEIA_SHA=${CHE_THEIA_SHA}"
  yarn --ignore-scripts
  popd >/dev/null

  # clone che-custom-nodejs-deasync
  git clone -b "master" --single-branch https://github.com/che-dockerfiles/che-custom-nodejs-deasync.git "${TMP_DIR}"/che-custom-nodejs-deasync
  if [[ ! -d "${TMP_DIR}"/che-custom-nodejs-deasync ]]; then echo "[ERR""OR] could not clone https://github.com/che-dockerfiles/che-custom-nodejs-deasync.git !"; exit 1; fi
fi

mkdir -p "${BREW_DOCKERFILE_ROOT_DIR}"
DOCKERFILES_ROOT_DIR=${TMP_DIR}/che-theia/dockerfiles

handle_che_theia_dev() {
  cd "${base_dir}"
  mkdir -p "${BREW_DOCKERFILE_ROOT_DIR}"/theia-dev

  # build only ubi8 image
  pushd "${DOCKERFILES_ROOT_DIR}"/theia-dev >/dev/null
  bash ./build.sh --dockerfile:Dockerfile.ubi8 --skip-tests --dry-run \
    --build-args:GITHUB_TOKEN=${GITHUB_TOKEN}
  ${DOCKER} build -f .Dockerfile -t "${TMP_THEIA_DEV_BUILDER_IMAGE}" . ${DOCKERFLAGS} --build-arg GITHUB_TOKEN=${GITHUB_TOKEN}
  if [[ $? -ne 0 ]]; then echo "[ERROR] Container build of ${TMP_THEIA_DEV_BUILDER_IMAGE} failed." exit 1; fi
# For use in default
  ${DOCKERRUN} tag "${TMP_THEIA_DEV_BUILDER_IMAGE}" eclipse/che-theia-dev:next
  popd >/dev/null
  
  # Create image theia-dev:ubi8-brew
  rm -rf "${DOCKERFILES_ROOT_DIR}"/theia-dev/docker/ubi8-brew
  cp -r "${DOCKERFILES_ROOT_DIR}"/theia-dev/docker/ubi8 "${DOCKERFILES_ROOT_DIR}"/theia-dev/docker/ubi8-brew
  # Add extra conf
  cp conf/theia-dev/ubi8-brew/* "${DOCKERFILES_ROOT_DIR}"/theia-dev/docker/ubi8-brew/
  sed -E -e "s/@@CRW_VERSION@@/${CRW_VERSION}/g" -i "${DOCKERFILES_ROOT_DIR}"/theia-dev/docker/ubi8-brew/post-env.dockerfile
  
  # dry-run for theia-dev:ubi8-brew to only generate Dockerfile
  pushd "${DOCKERFILES_ROOT_DIR}"/theia-dev >/dev/null
  bash ./build.sh --dockerfile:Dockerfile.ubi8-brew --skip-tests --dry-run \
    --build-args:GITHUB_TOKEN=${GITHUB_TOKEN}
  popd >/dev/null
  
  # Copy assets from ubi8 to local
  pushd "${BREW_DOCKERFILE_ROOT_DIR}"/theia-dev >/dev/null
  
  echo "Remove previous assets"
  rm -rf assets-*
  # copy assets
  cp -r "${CHE_THEIA_DIR}"/dockerfiles/theia-dev/asset-* . && ls -la asset-*
  # Copy src
  rm -rf src
  cp -r "${DOCKERFILES_ROOT_DIR}"/theia-dev/src .
  
  # Create asset with yarn cache
  # /usr/local/share/.cache/yarn/v*/ = yarn cache dir
  # /home/theia-dev/.yarn-global = yarn
  # /opt/app-root/src/.npm-global = yarn symlinks
  # ${DOCKERRUN} run --rm --entrypoint sh ${TMP_THEIA_DEV_BUILDER_IMAGE} -c 'ls -la \
  #   /usr/local/share/.cache/yarn/v*/ \
  #   /home/theia-dev/.yarn-global \
  #   /opt/app-root/src/.npm-global'
  ${DOCKERRUN} run --rm --entrypoint sh ${TMP_THEIA_DEV_BUILDER_IMAGE} -c 'tar -pzcf - \
    /usr/local/share/.cache/yarn/v*/ \
    /home/theia-dev/.yarn-global \
    /opt/app-root/src/.npm-global' > asset-yarn-$(uname -m).tgz

  popd >/dev/null
  
  # Copy generated Dockerfile
  mkdir -p "${BREW_DOCKERFILE_ROOT_DIR}"/theia-dev
  cp "${DOCKERFILES_ROOT_DIR}"/theia-dev/.Dockerfile "${BREW_DOCKERFILE_ROOT_DIR}"/theia-dev/Dockerfile

  echo "BEFORE SED ======= ${BREW_DOCKERFILE_ROOT_DIR}/theia-dev/Dockerfile =======>"
  cat "${BREW_DOCKERFILE_ROOT_DIR}"/theia-dev/Dockerfile
  echo "<======= ${BREW_DOCKERFILE_ROOT_DIR}/theia-dev/Dockerfile ======="

  # fix Dockerfile to use tarball instead of folder
  # -COPY asset-unpacked-generator ${HOME}/eclipse-che-theia-generator
  # +COPY asset-eclipse-che-theia-generator.tgz ${HOME}/eclipse-che-theia-generator.tgz
  # + RUN tar zxf eclipse-che-theia-generator.tgz && mv package eclipse-che-theia-generator
  newline='
'
  sed_in_place -e "s#COPY asset-unpacked-generator \${HOME}/eclipse-che-theia-generator#COPY asset-eclipse-che-theia-generator.tgz \${HOME}/eclipse-che-theia-generator.tgz\\${newline}RUN cd \${HOME} \&\& tar zxf eclipse-che-theia-generator.tgz \&\& mv package eclipse-che-theia-generator#" "${BREW_DOCKERFILE_ROOT_DIR}"/theia-dev/Dockerfile
 
  echo "AFTER SED ======= ${BREW_DOCKERFILE_ROOT_DIR}/theia-dev/Dockerfile =======>"
  cat "${BREW_DOCKERFILE_ROOT_DIR}"/theia-dev/Dockerfile
  echo "<======= ${BREW_DOCKERFILE_ROOT_DIR}/theia-dev/Dockerfile ======="

  # build local
  pushd "${BREW_DOCKERFILE_ROOT_DIR}"/theia-dev >/dev/null
  ${DOCKER} build -t ${CHE_THEIA_DEV_IMAGE_NAME} . ${DOCKERFLAGS} --build-arg GITHUB_TOKEN=${GITHUB_TOKEN}
  if [[ $? -ne 0 ]]; then echo "[ERROR] Container build of ${CHE_THEIA_DEV_IMAGE_NAME} failed." exit 1; fi
  popd >/dev/null

  # list generated assets & tarballs
  pushd "${BREW_DOCKERFILE_ROOT_DIR}"/theia-dev >/dev/null
  while IFS= read -r -d '' d; do
    echo "==== ${d} ====>"
    cat $d
    echo "<====  ${d} ===="
  done <   <(find . -type f -regextype posix-extended -iregex '.+(Dockerfile).*' -print0)

  # get list of assets to fetch into brew - ignore directories
  ls -1pd asset* | grep -E -v "/$" | sort | uniq | tee asset-list-$(uname -m).txt
  if [[ ! $(cat asset-list-$(uname -m).txt) ]]; then
    echo "[ERROR] Missing expected files in $(pwd) - build must exit!"
    exit 1
  fi
  popd >/dev/null

  # this stage creates quay.io/crw/theia-dev-rhel8:next but
  # theia build stage wants eclipse/che-theia-dev:next
  # see above, where we tag "${TMP_THEIA_DEV_BUILDER_IMAGE}" eclipse/che-theia-dev:next
}

# now do che-theia
handle_che_theia() {
  cd "${base_dir}"
  mkdir -p "${BREW_DOCKERFILE_ROOT_DIR}"/theia

  # build only ubi8 image and for target builder first, so we can extract data
  pushd "${DOCKERFILES_ROOT_DIR}"/theia >/dev/null
  # first generate the Dockerfile
  bash ./build.sh --dockerfile:Dockerfile.ubi8 --skip-tests --dry-run --tag:next --branch:${THEIA_BRANCH} --target:builder \
    --build-args:GITHUB_TOKEN=${GITHUB_TOKEN},DO_REMOTE_CHECK=false,DO_CLEANUP=false,THEIA_GITHUB_REPO=${THEIA_GITHUB_REPO},THEIA_COMMIT_SHA=${THEIA_COMMIT_SHA}    
  cp .Dockerfile .ubi8-dockerfile
  # Create one image for builder
  ${DOCKER} build -f .ubi8-dockerfile -t ${TMP_THEIA_BUILDER_IMAGE} --target builder . ${DOCKERFLAGS} \
    --build-arg GITHUB_TOKEN=${GITHUB_TOKEN} --build-arg THEIA_GITHUB_REPO=${THEIA_GITHUB_REPO} --build-arg THEIA_COMMIT_SHA=${THEIA_COMMIT_SHA}
  if [[ $? -ne 0 ]]; then echo "[ERROR] Container build of ${TMP_THEIA_BUILDER_IMAGE} failed." exit 1; fi
  # and create runtime image as well
  ${DOCKER} build -f .ubi8-dockerfile -t ${TMP_THEIA_RUNTIME_IMAGE} . ${DOCKERFLAGS} \
    --build-arg GITHUB_TOKEN=${GITHUB_TOKEN} --build-arg THEIA_GITHUB_REPO=${THEIA_GITHUB_REPO} --build-arg THEIA_COMMIT_SHA=${THEIA_COMMIT_SHA}
  if [[ $? -ne 0 ]]; then echo "[ERROR] Container build of ${TMP_THEIA_RUNTIME_IMAGE} failed." exit 1; fi
  popd >/dev/null
  
  # Create image theia-dev:ubi8-brew
  rm -rf "${DOCKERFILES_ROOT_DIR}"/theia/docker/ubi8-brew
  cp -r "${DOCKERFILES_ROOT_DIR}"/theia/docker/ubi8 "${DOCKERFILES_ROOT_DIR}"/theia/docker/ubi8-brew
  # Add extra conf
  cp conf/theia/ubi8-brew/* "${DOCKERFILES_ROOT_DIR}"/theia/docker/ubi8-brew/
  sed -E -e "s/@@CRW_VERSION@@/${CRW_VERSION}/g" -i "${DOCKERFILES_ROOT_DIR}"/theia/docker/ubi8-brew/runtime-post-env.dockerfile

  # dry-run for theia:ubi8-brew to only generate Dockerfile
  pushd "${DOCKERFILES_ROOT_DIR}"/theia >/dev/null
  bash ./build.sh --dockerfile:Dockerfile.ubi8-brew --skip-tests --dry-run --tag:next --branch:${THEIA_BRANCH} --target:builder \
    --build-args:GITHUB_TOKEN=${GITHUB_TOKEN},DO_REMOTE_CHECK=false,THEIA_GITHUB_REPO=${THEIA_GITHUB_REPO},THEIA_COMMIT_SHA=${THEIA_COMMIT_SHA}
  popd >/dev/null
  
  # workaround for building the endpoint
  # seems that this stage creates quay.io/crw/theia-rhel8:next (if local ubi-brew build is successful!) but
  # endpoint build stage wants eclipse/che-theia:next (which no longer exists on dockerhub)
  ${DOCKERRUN} tag "${TMP_THEIA_RUNTIME_IMAGE}" quay.io/crw/theia-rhel8:next
  ${DOCKERRUN} tag "${TMP_THEIA_RUNTIME_IMAGE}" eclipse/che-theia:next

  # Copy assets from ubi8 to local
  pushd "${BREW_DOCKERFILE_ROOT_DIR}"/theia >/dev/null

  # copy assets
  cp "${CHE_THEIA_DIR}"/dockerfiles/theia/asset-* .

  # npm/yarn cache
  # /usr/local/share/.cache/yarn/v*/ = yarn cache dir
  # /home/theia-dev/.yarn-global = yarn
  # /opt/app-root/src/.npm-global = yarn symlinks
  # ${DOCKERRUN} run --rm --entrypoint sh ${TMP_THEIA_BUILDER_IMAGE} -c 'ls -la \
  #   /usr/local/share/.cache/yarn/v*/ \
  #   /home/theia-dev/.yarn-global \
  #   /opt/app-root/src/.npm-global'
  ${DOCKERRUN} run --rm --entrypoint sh ${TMP_THEIA_BUILDER_IMAGE} -c 'tar -pzcf - \
    /usr/local/share/.cache/yarn/v*/ \
    /home/theia-dev/.yarn-global \
    /opt/app-root/src/.npm-global' > asset-yarn-$(uname -m).tar.gz
  
  # post-install dependencies
  # /home/theia-dev/theia-source-code/packages/debug-nodejs/download = node debug vscode binary
  # /home/theia-dev/theia-source-code/plugins/ = VS Code extensions
  # /tmp/vscode-ripgrep-cache-1.2.4 /tmp/vscode-ripgrep-cache-1.5.7 = rigrep binaries
  # /home/theia-dev/.cache = include electron/node-gyp cache
  ${DOCKERRUN} run --rm --entrypoint sh ${TMP_THEIA_BUILDER_IMAGE} -c 'ls -la /tmp/vscode-ripgrep-cache*'
  ${DOCKERRUN} run --rm --entrypoint sh ${TMP_THEIA_BUILDER_IMAGE} -c 'ls -la \
    /home/theia-dev/theia-source-code/dev-packages \
    /home/theia-dev/theia-source-code/node_modules \
    /home/theia-dev/theia-source-code/packages \
    /home/theia-dev/theia-source-code/plugins'
  ${DOCKERRUN} run --rm --entrypoint sh ${TMP_THEIA_BUILDER_IMAGE} -c 'tar -pzcf - \
    /home/theia-dev/theia-source-code/dev-packages  \
    /home/theia-dev/theia-source-code/packages  \
    /home/theia-dev/theia-source-code/plugins  \
    /tmp/vscode-ripgrep-cache-* \
    /home/theia-dev/.cache' > asset-post-download-dependencies-$(uname -m).tar.gz
  
  # node-headers
  download_url="https://nodejs.org/download/release/v${nodeVersion}/node-v${nodeVersion}-headers.tar.gz"
  echo -n "Local node version: "; node --version
  echo "Requested node version: v${nodeVersion}"
  echo "URL to curl: ${download_url}"
  curl -sSL "${download_url}" -o asset-node-headers.tar.gz
  # ${DOCKERRUN} run --rm --entrypoint sh ${TMP_THEIA_BUILDER_IMAGE} -c 'nodeVersion=$(node --version); \
  # download_url="https://nodejs.org/download/release/${nodeVersion}/node-${nodeVersion}-headers.tar.gz" && curl ${download_url}' > asset-node-headers.tar.gz
  
  # Add yarn.lock after compilation
  ${DOCKERRUN} run --rm --entrypoint sh ${TMP_THEIA_BUILDER_IMAGE} -c 'cat /home/theia-dev/theia-source-code/yarn.lock' > asset-yarn-$(uname -m).lock

  # Theia source code
  ${DOCKERRUN} run --rm --entrypoint sh ${TMP_THEIA_BUILDER_IMAGE} -c 'cat /home/theia-dev/theia-source-code.tgz' > asset-theia-source-code.tar.gz

  # npm/yarn cache
  # /usr/local/share/.cache/yarn/v*/ = yarn cache dir
  # /opt/app-root/src/.npm-global = npm global
  # ${DOCKERRUN} run --rm --entrypoint sh ${TMP_THEIA_RUNTIME_IMAGE} -c 'ls -la \
  #   /usr/local/share/.cache/yarn/v*/ \
  #   /opt/app-root/src/.npm-global'
  ${DOCKERRUN} run --rm --entrypoint sh ${TMP_THEIA_RUNTIME_IMAGE} -c 'tar -pzcf - \
    /usr/local/share/.cache/yarn/v*/ \
    /opt/app-root/src/.npm-global' > asset-yarn-runtime-image-$(uname -m).tar.gz

  # Save sshpass sources
  ${DOCKERRUN} run --rm --entrypoint sh ${TMP_THEIA_RUNTIME_IMAGE} -c 'cat /opt/app-root/src/sshpass.tar.gz' > asset-sshpass-sources.tar.gz

  rm -rf src
  cp -r "${DOCKERFILES_ROOT_DIR}"/theia/src .
  
  # Copy generated Dockerfile
  mkdir -p "${BREW_DOCKERFILE_ROOT_DIR}"/theia
  cp "${DOCKERFILES_ROOT_DIR}"/theia/.Dockerfile "${BREW_DOCKERFILE_ROOT_DIR}"/theia/Dockerfile

  # Copy branding files
  cp -r "${base_dir}"/conf/theia/branding "${BREW_DOCKERFILE_ROOT_DIR}"/theia

  echo "========= ${BREW_DOCKERFILE_ROOT_DIR}/theia/Dockerfile =========>"
  cat Dockerfile
  echo "<========= ${BREW_DOCKERFILE_ROOT_DIR}/theia/Dockerfile ========="

  # build local 
  # https://github.com/eclipse/che/issues/16844 -- fails in Jenkins and locally since 7.12 so comment out 
  pushd "${BREW_DOCKERFILE_ROOT_DIR}"/theia >/dev/null
  ${DOCKER} build -t ${CHE_THEIA_IMAGE_NAME} . ${DOCKERFLAGS} \
   --build-arg GITHUB_TOKEN=${GITHUB_TOKEN} --build-arg THEIA_GITHUB_REPO=${THEIA_GITHUB_REPO} --build-arg THEIA_COMMIT_SHA=${THEIA_COMMIT_SHA} \
   2>&1 | tee /tmp/CHE_THEIA_IMAGE_NAME_buildlog.txt
  # NONZERO="$(egrep "a non-zero code:|Exit code: 1|Command failed"  /tmp/CHE_THEIA_IMAGE_NAME_buildlog.txt || true)"
  # if [[ $? -ne 0 ]] || [[ $NONZERO ]]; then 
  #  echo "[ERROR] Container build of ${CHE_THEIA_IMAGE_NAME} failed: "
  #  echo "${NONZERO}"
  #  exit 1
  # fi
  popd >/dev/null

  # Set the CDN options inside the Dockerfile
  sed_in_place -r -e 's#ARG CDN_PREFIX=.+#ARG CDN_PREFIX="https://static.developers.redhat.com/che/crw_theia_artifacts/"#' "${BREW_DOCKERFILE_ROOT_DIR}"/theia/Dockerfile
  sed_in_place -r -e 's#ARG MONACO_CDN_PREFIX=.+#ARG MONACO_CDN_PREFIX="https://cdn.jsdelivr.net/npm/"#' "${BREW_DOCKERFILE_ROOT_DIR}"/theia/Dockerfile

  # verify that CDN is enabled
  grep -E "https://static.developers.redhat.com/che/crw_theia_artifacts/" "${BREW_DOCKERFILE_ROOT_DIR}"/theia/Dockerfile || exit 1
  grep -E "https://cdn.jsdelivr.net/npm/" "${BREW_DOCKERFILE_ROOT_DIR}"/theia/Dockerfile || exit 1

  # TODO: should we use some other Dockerfile?
  echo "-=-=-=- dockerfiles -=-=-=->"
  find "${DOCKERFILES_ROOT_DIR}"/ -name "*ockerfile*" | egrep -v "alpine|e2e"
  echo "<-=-=-=- dockerfiles -=-=-=-"

  # list generated assets & tarballs
  pushd "${BREW_DOCKERFILE_ROOT_DIR}"/theia >/dev/null
  while IFS= read -r -d '' d; do
    echo "==== ${d} ====>"
    cat $d
    echo "<====  ${d} ===="
  done <   <(find . -type f -regextype posix-extended -iregex '.+(Dockerfile).*' -print0)

  # create asset-branding.tar.gz from branding folder contents
  tar -pcvzf asset-branding.tar.gz branding/*

  # get list of assets to fetch into brew - ignore directories
  ls -1pd asset* | grep -E -v "/$" | sort | uniq | tee asset-list-$(uname -m).txt
  if [[ ! $(cat asset-list-$(uname -m).txt) ]]; then
    echo "[ERROR] Missing expected files in $(pwd) - build must exit!"
    exit 1
  fi

  # workaround for building the endpoint
  # seems that this stage creates quay.io/crw/theia-rhel8:next (if local ubi-brew build is successful!) but
  # endpoint build stage wants eclipse/che-theia:next (which no longer exists on dockerhub)
  ${DOCKERRUN} tag "${TMP_THEIA_RUNTIME_IMAGE}" eclipse/che-theia:next
}

# now do che-theia-endpoint-runtime-binary
handle_che_theia_endpoint_runtime_binary() {
  # build/pull che-custom-nodejs-deasync
  nodeRepo=$(grep -E 'FROM .*che-custom-nodejs-deasync.*' "${DOCKERFILES_ROOT_DIR}"/theia-endpoint-runtime-binary/docker/ubi8/builder-from.dockerfile  | cut -d' ' -f2 | cut -d':' -f1)
  { ${DOCKER} pull ${nodeRepo}:$nodeVersion; rc=$?; }
  if [[ $rc -ne 0 ]] ; then
    cd "${TMP_DIR}"/che-custom-nodejs-deasync
    echo "$nodeVersion" > VERSION
    ${DOCKER} build -f Dockerfile -t ${TMP_CHE_CUSTOM_NODEJS_DEASYNC_IMAGE} . ${DOCKERFLAGS} \
      --build-arg NODE_VERSION=${nodeVersion}
  else
    docker tag ${nodeRepo}:$nodeVersion ${TMP_CHE_CUSTOM_NODEJS_DEASYNC_IMAGE}
    docker rmi ${nodeRepo}:$nodeVersion
  fi
  sed -E -e "s|(FROM ).*che-custom-nodejs-deasync[^ ]*(.*)|\1 ${TMP_CHE_CUSTOM_NODEJS_DEASYNC_IMAGE} \2|g" -i "${DOCKERFILES_ROOT_DIR}"/theia-endpoint-runtime-binary/docker/ubi8/builder-from.dockerfile

  cd "${base_dir}"
  mkdir -p "${BREW_DOCKERFILE_ROOT_DIR}"/theia-endpoint-runtime-binary

  # build only ubi8 image and for target builder first, so we can extract data
  pushd "${DOCKERFILES_ROOT_DIR}"/theia-endpoint-runtime-binary >/dev/null
  # first generate the Dockerfile
  bash ./build.sh --dockerfile:Dockerfile.ubi8 --skip-tests --dry-run --tag:next --target:builder \
    --build-args:GITHUB_TOKEN=${GITHUB_TOKEN},DO_REMOTE_CHECK=false 
  # keep a copy of the file
  cp .Dockerfile .ubi8-dockerfile
  # Create one image for builder target
  ${DOCKER} build -f .ubi8-dockerfile -t ${TMP_THEIA_ENDPOINT_BINARY_BUILDER_IMAGE} --target builder . ${DOCKERFLAGS} \
    --build-arg GITHUB_TOKEN=${GITHUB_TOKEN}
  if [[ $? -ne 0 ]]; then echo "[ERROR] Container build of ${TMP_THEIA_ENDPOINT_BINARY_BUILDER_IMAGE} failed." exit 1; fi
  popd >/dev/null

  # Create image theia-endpoint-runtime-binary:ubi8-brew
  rm -rf "${DOCKERFILES_ROOT_DIR}"/theia-endpoint-runtime-binary/docker/ubi8-brew
  cp -r "${DOCKERFILES_ROOT_DIR}"/theia-endpoint-runtime-binary/docker/ubi8 "${DOCKERFILES_ROOT_DIR}"/theia-endpoint-runtime-binary/docker/ubi8-brew

  # Add extra conf
  cp conf/theia-endpoint-runtime-binary/ubi8-brew/* "${DOCKERFILES_ROOT_DIR}"/theia-endpoint-runtime-binary/docker/ubi8-brew/
  sed -E -e "s/@@CRW_VERSION@@/${CRW_VERSION}/g" -i "${DOCKERFILES_ROOT_DIR}"/theia-endpoint-runtime-binary/docker/ubi8-brew/runtime-post-env.dockerfile

  # dry-run for theia-endpoint-runtime:ubi8-brew to only generate Dockerfile
  pushd "${DOCKERFILES_ROOT_DIR}"/theia-endpoint-runtime-binary >/dev/null
  bash ./build.sh --dockerfile:Dockerfile.ubi8-brew --skip-tests --dry-run --tag:next --target:builder \
    --build-args:GITHUB_TOKEN=${GITHUB_TOKEN},DO_REMOTE_CHECK=false
  popd >/dev/null
  
  # Copy assets from ubi8 to local
  pushd "${BREW_DOCKERFILE_ROOT_DIR}"/theia-endpoint-runtime-binary >/dev/null

  # npm/yarn cache
  # /usr/local/share/.cache/yarn/v*/ = yarn cache dir
  # /usr/local/share/.config/yarn/global
  # /opt/app-root/src/.npm-global = yarn symlinks
  # ${DOCKERRUN} run --rm --entrypoint sh ${TMP_THEIA_ENDPOINT_BINARY_BUILDER_IMAGE} -c 'ls -la \
  #   /usr/local/share/.cache/yarn/v*/ \
  #   /usr/local/share/.config/yarn/global'
  ${DOCKERRUN} run --rm --entrypoint sh ${TMP_THEIA_ENDPOINT_BINARY_BUILDER_IMAGE} -c 'tar -pzcf - \
    /usr/local/share/.cache/yarn/v*/ \
    /usr/local/share/.config/yarn/global' > asset-theia-endpoint-runtime-binary-yarn-$(uname -m).tar.gz
  
  ${DOCKERRUN} run --rm --entrypoint sh ${TMP_THEIA_ENDPOINT_BINARY_BUILDER_IMAGE} -c \
    'cd /home/theia/ && tar -pzcf - pre-assembly-nodejs-static' > asset-theia-endpoint-runtime-pre-assembly-nodejs-static-$(uname -m).tar.gz

  # node-src
  download_url="https://nodejs.org/download/release/v${nodeVersion}/node-v${nodeVersion}.tar.gz"
  echo -n "Local node version: "; node --version
  echo "Requested node version: v${nodeVersion}"
  echo "URL to curl: ${download_url}"
  curl -sSL "${download_url}" -o asset-node-src.tar.gz
  # ${DOCKERRUN} run --rm --entrypoint sh ${TMP_THEIA_ENDPOINT_BINARY_BUILDER_IMAGE} -c 'nodeVersion=$(node --version); \
  # download_url="https://nodejs.org/download/release/${nodeVersion}/node-${nodeVersion}.tar.gz" && curl ${download_url}' > asset-node-src.tar.gz
  
  # Copy generated Dockerfile
  cp "${DOCKERFILES_ROOT_DIR}"/theia-endpoint-runtime-binary/.Dockerfile "${BREW_DOCKERFILE_ROOT_DIR}"/theia-endpoint-runtime-binary/Dockerfile
  
  # build local
  ${DOCKER} build -t ${CHE_THEIA_ENDPOINT_BINARY_IMAGE_NAME} . ${DOCKERFLAGS} \
    --build-arg GITHUB_TOKEN=${GITHUB_TOKEN} --build-arg THEIA_GITHUB_REPO=${THEIA_GITHUB_REPO} --build-arg THEIA_COMMIT_SHA=${THEIA_COMMIT_SHA}
  if [[ $? -ne 0 ]]; then echo "[ERROR] Container build of ${CHE_THEIA_ENDPOINT_BINARY_IMAGE_NAME} failed." exit 1; fi
  popd >/dev/null

  # list generated assets & tarballs
  pushd "${BREW_DOCKERFILE_ROOT_DIR}"/theia-endpoint-runtime-binary >/dev/null
  while IFS= read -r -d '' d; do
    echo "==== ${d} ====>"
    cat $d
    echo "<====  ${d} ===="
  done <   <(find . -type f -regextype posix-extended -iregex '.+(Dockerfile).*' -print0)

  # get list of assets to fetch into brew - ignore directories
  ls -1pd asset* | grep -E -v "/$" | sort | uniq | tee asset-list-$(uname -m).txt
  if [[ ! $(cat asset-list-$(uname -m).txt) ]]; then
    echo "[ERROR] Missing expected files in $(pwd) - build must exit!"
    exit 1
  fi

  popd >/dev/null
}

for step in $STEPS; do
  echo 
  echo "=========================================================="
  echo "====== $step"
  echo "=========================================================="
  $step
done

# optional cleanup of generated images
if [[ ${DELETE_TMP_IMAGES} -eq 1 ]] || [[ ${DELETE_ALL_IMAGES} -eq 1 ]]; then
  echo;echo "Delete temp images from container registry"
  ${DOCKERRUN} rmi -f $TMP_THEIA_DEV_BUILDER_IMAGE $TMP_THEIA_BUILDER_IMAGE $TMP_THEIA_RUNTIME_IMAGE $TMP_THEIA_ENDPOINT_BUILDER_IMAGE $TMP_THEIA_ENDPOINT_BINARY_BUILDER_IMAGE $TMP_CHE_CUSTOM_NODEJS_DEASYNC_IMAGE || true
fi
if [[ ${DELETE_ALL_IMAGES} -eq 1 ]]; then
  echo;echo "Delete che-theia images from container registry"
  ${DOCKERRUN} rmi -f $CHE_THEIA_DEV_IMAGE_NAME $CHE_THEIA_IMAGE_NAME $CHE_THEIA_ENDPOINT_IMAGE_NAME $CHE_THEIA_ENDPOINT_BINARY_IMAGE_NAME || true
fi

set +x
echo; echo "Dockerfiles and tarballs generated. See the following folder(s) for content to upload to pkgs.devel.redhat.com:"
for step in $STEPS; do
  output_dir=${step//_/-};output_dir=${output_dir/handle-che-/}
  echo " - ${BREW_DOCKERFILE_ROOT_DIR}/${output_dir}"
done
echo
