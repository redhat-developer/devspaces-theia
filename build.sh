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
  $0 --ctb CHE_THEIA_BRANCH --tb THEIA_BRANCH --tgr THEIA_GITHUB_REPO [options] 

Example:
  $0 --ctb 7.9.0 --tb crw-2.1.0.rc1 --tgr redhat-developer/eclipse-theia --all --no-tests --no-cache 
  $0 --ctb master --tb master --tgr eclipse-theia/theia -d -t --no-cache --rmi:tmp --squash

Options: 
  $0 -d      | build theia-dev
  $0 -t      | build (or rebuild) theia. Note: if theia-dev not already built, must add -d flag too
  $0 -b      | build (or rebuild) theia-endpoint-runtime-binary. Note: if theia-dev not already built, must add -d flag too
  $0 --all   | build 3 projects: theia-dev, theia, theia-endpoint-runtime-binary

Note that steps are run in the order specified, so always start with -d if needed.

Additional flags:

  --tgr      | container build arg THEIA_GITHUB_REPO from which to get theia sources, 
             | default: eclipse-theia/theia; optional: redhat-developer/eclipse-theia
  --squash   | if running docker in experimental mode, squash images
  --no-cache | do not use docker cache

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

CHE_THEIA_BRANCH="master"
THEIA_BRANCH="master"
THEIA_GITHUB_REPO="eclipse-theia/theia" # or redhat-developer/eclipse-theia so we can build from a tag instead of a random commit SHA
for key in "$@"; do
  case $key in 
      '--ctb') CHE_THEIA_BRANCH="$2"; shift 2;;
      '--tb') THEIA_BRANCH="$2"; shift 2;;
      '--tgr') THEIA_GITHUB_REPO="$2"; shift 2;;
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
  esac
done

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
        sed -i $d -e "s@test(\(.\+async () => {\)@test.skip(\1@g"
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
        sed -i $d -e "s@test(\(.\+() => {\)@test.skip(\1@g"
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
  yarn
  popd >/dev/null
  
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
  docker build -f .Dockerfile -t "${TMP_THEIA_DEV_BUILDER_IMAGE}" . ${DOCKERFLAGS} --build-arg GITHUB_TOKEN=${GITHUB_TOKEN}
  # For use in default
  docker tag "${TMP_THEIA_DEV_BUILDER_IMAGE}" eclipse/che-theia-dev:next
  popd >/dev/null
  
  # Create image theia-dev:ubi8-brew
  rm -rf "${DOCKERFILES_ROOT_DIR}"/theia-dev/docker/ubi8-brew
  cp -r "${DOCKERFILES_ROOT_DIR}"/theia-dev/docker/ubi8 "${DOCKERFILES_ROOT_DIR}"/theia-dev/docker/ubi8-brew
  # Add extra conf
  cp conf/theia-dev/ubi8-brew/* "${DOCKERFILES_ROOT_DIR}"/theia-dev/docker/ubi8-brew/
  
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
  cp "${CHE_THEIA_DIR}"/dockerfiles/theia-dev/asset-* .
  # Copy src
  rm -rf src
  cp -r "${DOCKERFILES_ROOT_DIR}"/theia-dev/src .
  
  # Create asset with yarn cache
  # /usr/local/share/.cache/yarn/v4 = yarn cache dir
  # /home/theia-dev/.yarn-global = yarn
  # /opt/app-root/src/.npm-global = yarn symlinks
  docker run --rm --entrypoint sh ${TMP_THEIA_DEV_BUILDER_IMAGE} -c 'ls -la \
    /usr/local/share/.cache/yarn/v4 \
    /home/theia-dev/.yarn-global \
    /opt/app-root/src/.npm-global || true'
  docker run --rm --entrypoint sh ${TMP_THEIA_DEV_BUILDER_IMAGE} -c 'tar -pzcf - \
    /usr/local/share/.cache/yarn/v4 \
    /home/theia-dev/.yarn-global \
    /opt/app-root/src/.npm-global' > asset-yarn.tgz
  popd >/dev/null
  
  # Copy generate Dockerfile
  mkdir -p "${BREW_DOCKERFILE_ROOT_DIR}"/theia-dev
  cp "${DOCKERFILES_ROOT_DIR}"/theia-dev/.Dockerfile "${BREW_DOCKERFILE_ROOT_DIR}"/theia-dev/Dockerfile

  # build local
  pushd "${BREW_DOCKERFILE_ROOT_DIR}"/theia-dev >/dev/null
  docker build -t ${CHE_THEIA_DEV_IMAGE_NAME} . ${DOCKERFLAGS} --build-arg GITHUB_TOKEN=${GITHUB_TOKEN}
  popd >/dev/null

  # list generated assets & tarballs
  pushd "${BREW_DOCKERFILE_ROOT_DIR}"/theia-dev >/dev/null
  while IFS= read -r -d '' d; do
    echo "==== ${d} ====>"
    cat $d
    echo "<====  ${d} ===="
  done <   <(find . -type f -regextype posix-extended -iregex '.+(Dockerfile).*' -print0)
  ls -laR asset* *gz || echo "[ERROR] Missing expected files in ${BREW_DOCKERFILE_ROOT_DIR}/theia-dev - build must exit!"
  popd >/dev/null

  # this stage creates quay.io/crw/theia-dev-rhel8:next but
  # theia build stage wants eclipse/che-theia-dev:next
  # see above, where we docker tag "${TMP_THEIA_DEV_BUILDER_IMAGE}" eclipse/che-theia-dev:next
}

# now do che-theia
handle_che_theia() {
  cd "${base_dir}"
  mkdir -p "${BREW_DOCKERFILE_ROOT_DIR}"/theia

  # build only ubi8 image and for target builder first, so we can extract data
  pushd "${DOCKERFILES_ROOT_DIR}"/theia >/dev/null
  # first generate the Dockerfile
  bash ./build.sh --dockerfile:Dockerfile.ubi8 --skip-tests --dry-run --tag:next --branch:${THEIA_BRANCH} --target:builder \
    --build-args:GITHUB_TOKEN=${GITHUB_TOKEN},DO_REMOTE_CHECK=false,DO_CLEANUP=false,THEIA_GITHUB_REPO=${THEIA_GITHUB_REPO}    
  cp .Dockerfile .ubi8-dockerfile
  # Create one image for builder
  docker build -f .ubi8-dockerfile -t ${TMP_THEIA_BUILDER_IMAGE} --target builder . ${DOCKERFLAGS} \
    --build-arg GITHUB_TOKEN=${GITHUB_TOKEN} --build-arg THEIA_GITHUB_REPO=${THEIA_GITHUB_REPO}
  # and create runtime image as well
  docker build -f .ubi8-dockerfile -t ${TMP_THEIA_RUNTIME_IMAGE} . ${DOCKERFLAGS} \
    --build-arg GITHUB_TOKEN=${GITHUB_TOKEN} --build-arg THEIA_GITHUB_REPO=${THEIA_GITHUB_REPO}
  popd >/dev/null
  
  # Create image theia-dev:ubi8-brew
  rm -rf "${DOCKERFILES_ROOT_DIR}"/theia/docker/ubi8-brew
  cp -r "${DOCKERFILES_ROOT_DIR}"/theia/docker/ubi8 "${DOCKERFILES_ROOT_DIR}"/theia/docker/ubi8-brew
  # Add extra conf
  cp conf/theia/ubi8-brew/* "${DOCKERFILES_ROOT_DIR}"/theia/docker/ubi8-brew/
  
  # dry-run for theia:ubi8-brew to only generate Dockerfile
  pushd "${DOCKERFILES_ROOT_DIR}"/theia >/dev/null
  bash ./build.sh --dockerfile:Dockerfile.ubi8-brew --skip-tests --dry-run --tag:next --branch:${THEIA_BRANCH} --target:builder \
    --build-args:GITHUB_TOKEN=${GITHUB_TOKEN},DO_REMOTE_CHECK=false,THEIA_GITHUB_REPO=${THEIA_GITHUB_REPO}    
  popd >/dev/null
  
  # Copy assets from ubi8 to local
  pushd "${BREW_DOCKERFILE_ROOT_DIR}"/theia >/dev/null

  # copy assets
  cp "${CHE_THEIA_DIR}"/dockerfiles/theia/asset-* .

  # npm/yarn cache
  # /usr/local/share/.cache/yarn/v4 = yarn cache dir
  # /home/theia-dev/.yarn-global = yarn
  # /opt/app-root/src/.npm-global = yarn symlinks
  docker run --rm --entrypoint sh ${TMP_THEIA_BUILDER_IMAGE} -c 'ls -la \
    /usr/local/share/.cache/yarn/v4 \
    /home/theia-dev/.yarn-global \
    /opt/app-root/src/.npm-global || true'
  docker run --rm --entrypoint sh ${TMP_THEIA_BUILDER_IMAGE} -c 'tar -pzcf - \
    /usr/local/share/.cache/yarn/v4 \
    /home/theia-dev/.yarn-global \
    /opt/app-root/src/.npm-global' > asset-yarn.tar.gz
  
  # post-install dependencies
  # /home/theia-dev/theia-source-code/packages/debug-nodejs/download = node debug vscode binary
  # /home/theia-dev/theia-source-code/plugins/ = VS Code extensions
  # /tmp/vscode-ripgrep-cache-1.2.4 /tmp/vscode-ripgrep-cache-1.5.7 = rigrep binaries
  # /home/theia-dev/.cache = include electron/node-gyp cache
  docker run --rm --entrypoint sh ${TMP_THEIA_BUILDER_IMAGE} -c 'ls -la /tmp/vscode-ripgrep-cache*'
  docker run --rm --entrypoint sh ${TMP_THEIA_BUILDER_IMAGE} -c 'tar -pzcf - \
    /home/theia-dev/theia-source-code/packages/debug-nodejs/download  \
    /tmp/vscode-ripgrep-cache-* \
    /home/theia-dev/theia-source-code/plugins/  \
    /home/theia-dev/.cache' > asset-post-download-dependencies.tar.gz
  
  # node-headers
  docker run --rm --entrypoint sh ${TMP_THEIA_BUILDER_IMAGE} -c 'nodeVersion=$(node --version); download_url="https://nodejs.org/download/release/${nodeVersion}/node-${nodeVersion}-headers.tar.gz" && curl ${download_url}' > asset-node-headers.tar.gz
  
  # Add yarn.lock after compilation
  docker run --rm --entrypoint sh ${TMP_THEIA_BUILDER_IMAGE} -c 'cat /home/theia-dev/theia-source-code/yarn.lock' > asset-yarn.lock

  # Theia source code
  docker run --rm --entrypoint sh ${TMP_THEIA_BUILDER_IMAGE} -c 'cat /home/theia-dev/theia-source-code.tgz' > asset-theia-source-code.tar.gz

  # npm/yarn cache
  # /usr/local/share/.cache/yarn/v4 = yarn cache dir
  # /opt/app-root/src/.npm-global = npm global
  docker run --rm --entrypoint sh ${TMP_THEIA_RUNTIME_IMAGE} -c 'ls -la \
    /usr/local/share/.cache/yarn/v4 \
    /opt/app-root/src/.npm-global || true'
  docker run --rm --entrypoint sh ${TMP_THEIA_RUNTIME_IMAGE} -c 'tar -pzcf - \
    /usr/local/share/.cache/yarn/v4 \
    /opt/app-root/src/.npm-global' > asset-yarn-runtime-image.tar.gz

  rm -rf src
  cp -r "${DOCKERFILES_ROOT_DIR}"/theia/src .
  
  # Copy generate Dockerfile
  mkdir -p "${BREW_DOCKERFILE_ROOT_DIR}"/theia
  cp "${DOCKERFILES_ROOT_DIR}"/theia/.Dockerfile "${BREW_DOCKERFILE_ROOT_DIR}"/theia/Dockerfile

  # Copy branding files
  cp -r "${base_dir}"/conf/theia/branding "${BREW_DOCKERFILE_ROOT_DIR}"/theia

  # build local
  pushd "${BREW_DOCKERFILE_ROOT_DIR}"/theia >/dev/null
  docker build -t ${CHE_THEIA_IMAGE_NAME} . ${DOCKERFLAGS} \
    --build-arg GITHUB_TOKEN=${GITHUB_TOKEN} --build-arg THEIA_GITHUB_REPO=${THEIA_GITHUB_REPO}
  popd >/dev/null

  # Set the CDN options inside the docker file
  sed -i "${BREW_DOCKERFILE_ROOT_DIR}"/theia/Dockerfile -r \
      -e 's#ARG CDN_PREFIX=.+#ARG CDN_PREFIX="https://static.developers.redhat.com/che/crw_theia_artifacts/"#' \
      -e 's#ARG MONACO_CDN_PREFIX=.+#ARG MONACO_CDN_PREFIX="https://cdn.jsdelivr.net/npm/"#'

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
  # check branding folder too
  ls -laR asset* *gz branding || echo "[ERROR] Missing expected files in ${BREW_DOCKERFILE_ROOT_DIR}/theia - build must exit!"
  popd >/dev/null

  # workaround for building the endpoint
  # seems that this stage creates quay.io/crw/theia-rhel8:next but
  # endpoint build stage wants eclipse/che-theia:next (which no longer exists on dockerhub)
  docker tag "${TMP_THEIA_RUNTIME_IMAGE}" eclipse/che-theia:next
}

# now do che-theia-endpoint-runtime-binary
handle_che_theia_endpoint_runtime_binary() {
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
  docker build -f .ubi8-dockerfile -t ${TMP_THEIA_ENDPOINT_BINARY_BUILDER_IMAGE} --target builder . ${DOCKERFLAGS} \
    --build-arg GITHUB_TOKEN=${GITHUB_TOKEN}
  popd >/dev/null

  # Create image theia-endpoint-runtime-binary:ubi8-brew
  rm -rf "${DOCKERFILES_ROOT_DIR}"/theia-endpoint-runtime-binary/docker/ubi8-brew
  cp -r "${DOCKERFILES_ROOT_DIR}"/theia-endpoint-runtime-binary/docker/ubi8 "${DOCKERFILES_ROOT_DIR}"/theia-endpoint-runtime-binary/docker/ubi8-brew

  # Add extra conf
  cp conf/theia-endpoint-runtime-binary/ubi8-brew/* "${DOCKERFILES_ROOT_DIR}"/theia-endpoint-runtime-binary/docker/ubi8-brew/

  # dry-run for theia-endpoint-runtime:ubi8-brew to only generate Dockerfile
  pushd "${DOCKERFILES_ROOT_DIR}"/theia-endpoint-runtime-binary >/dev/null
  bash ./build.sh --dockerfile:Dockerfile.ubi8-brew --skip-tests --dry-run --tag:next --target:builder \
    --build-args:GITHUB_TOKEN=${GITHUB_TOKEN},DO_REMOTE_CHECK=false
  popd >/dev/null
  
  # Copy assets from ubi8 to local
  pushd "${BREW_DOCKERFILE_ROOT_DIR}"/theia-endpoint-runtime-binary >/dev/null

  # npm/yarn cache
  # /usr/local/share/.cache/yarn/v4 = yarn cache dir
  # /usr/local/share/.config/yarn/global
  # /opt/app-root/src/.npm-global = yarn symlinks
  docker run --rm --entrypoint sh ${TMP_THEIA_ENDPOINT_BINARY_BUILDER_IMAGE} -c 'ls -la \
    /usr/local/share/.cache/yarn/v4 \
    /usr/local/share/.config/yarn/global || true'
  docker run --rm --entrypoint sh ${TMP_THEIA_ENDPOINT_BINARY_BUILDER_IMAGE} -c 'tar -pzcf - \
    /usr/local/share/.cache/yarn/v4 \
    /usr/local/share/.config/yarn/global' > asset-theia-endpoint-runtime-binary-yarn.tar.gz
  
  # node
  docker run --rm --entrypoint sh ${TMP_THEIA_ENDPOINT_BINARY_BUILDER_IMAGE} \
    -c 'nodeVersion=$(node --version); download_url="https://nodejs.org/download/release/${nodeVersion}/node-${nodeVersion}.tar.gz" && curl ${download_url}' \
    > asset-node-src.tar.gz
  
  # Copy generate Dockerfile
  cp "${DOCKERFILES_ROOT_DIR}"/theia-endpoint-runtime-binary/.Dockerfile "${BREW_DOCKERFILE_ROOT_DIR}"/theia-endpoint-runtime-binary/Dockerfile
  
  # build local
  docker build -t ${CHE_THEIA_ENDPOINT_BINARY_IMAGE_NAME} . ${DOCKERFLAGS} \
    --build-arg GITHUB_TOKEN=${GITHUB_TOKEN} --build-arg THEIA_GITHUB_REPO=${THEIA_GITHUB_REPO}
  popd >/dev/null

  # list generated assets & tarballs
  pushd "${BREW_DOCKERFILE_ROOT_DIR}"/theia-endpoint-runtime-binary >/dev/null
  while IFS= read -r -d '' d; do
    echo "==== ${d} ====>"
    cat $d
    echo "<====  ${d} ===="
  done <   <(find . -type f -regextype posix-extended -iregex '.+(Dockerfile).*' -print0)
  ls -laR asset* *gz || echo "[ERROR] Missing expected files in ${BREW_DOCKERFILE_ROOT_DIR}/theia-endpoint-runtime-binary - build must exit!"
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
  echo;echo "Delete temp images from docker registry"
  docker rmi -f $TMP_THEIA_DEV_BUILDER_IMAGE $TMP_THEIA_BUILDER_IMAGE $TMP_THEIA_RUNTIME_IMAGE $TMP_THEIA_ENDPOINT_BUILDER_IMAGE $TMP_THEIA_ENDPOINT_BINARY_BUILDER_IMAGE
fi
if [[ ${DELETE_ALL_IMAGES} -eq 1 ]]; then
  echo;echo "Delete che-theia images from docker registry"
  docker rmi -f $CHE_THEIA_DEV_IMAGE_NAME $CHE_THEIA_IMAGE_NAME $CHE_THEIA_ENDPOINT_IMAGE_NAME $CHE_THEIA_ENDPOINT_BINARY_IMAGE_NAME
fi

echo; echo "Dockerfiles and tarballs generated. See the following folder(s) for content to upload to pkgs.devel.redhat.com:"
for step in $STEPS; do
  output_dir=${step//_/-};output_dir=${output_dir/handle-che-/}
  echo " - ${BREW_DOCKERFILE_ROOT_DIR}/${output_dir}"
done
echo
