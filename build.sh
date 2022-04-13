#!/bin/bash
# Copyright (c) 2019-2022 Red Hat, Inc.
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

# defaults
nodeVersion="14.18.2" # version of node to use for theia containers (aligned to version in ubi base images)
# see https://catalog.redhat.com/software/containers/ubi8/nodejs-12/5d3fff015a13461f5fb8635a?container-tabs=packages or run
# podman run -it --rm --entrypoint /bin/bash registry.redhat.io/ubi8/nodejs-12 -c "node -v"
CRW_VERSION="" # must set this via cmdline with --cv, or use --cb to set MIDSTM_BRANCH
MIDSTM_BRANCH="" # must set this via cmdline with --cb, or use --cv to set CRW_VERSION
SOURCE_BRANCH="master"
THEIA_BRANCH="master"
THEIA_GITHUB_REPO="eclipse-theia/theia" # or redhat-developer/eclipse-theia so we can build from a tag instead of a random commit SHA
THEIA_COMMIT_SHA=""
BUILD_TYPE="tmp" # use "tmp" prefix for temporary build tags via GH actions, but if we're building based on a PR, set "pr" prefix

# load defaults from file, if it exists
if [[ -r ./BUILD_PARAMS ]]; then source ./BUILD_PARAMS; fi

usage () {
  set +u
  if [[ -z $GITHUB_TOKEN ]]; then 
    echo "
You must export a GITHUB_TOKEN to your shell before running this script, or you will be rate-limited and the build will fail.
See https://github.com/settings/tokens for more information.
"
  fi
  set -u
  echo "Usage:
  export GITHUB_TOKEN=*your token here*
  $0 --ctb CHE_THEIA_BRANCH [options]

Examples:
  $(if [[ -r ./BUILD_COMMAND ]]; then cat ./BUILD_COMMAND; fi)

  $0 --ctb ${SOURCE_BRANCH} --all --no-cache --no-tests --rmi:tmp --cb devspaces-3.y-rhel-8
  $0 --ctb ${SOURCE_BRANCH} --all --no-cache --no-tests --rmi:tmp --cv 3.y

Options:
  $0 -d      | build theia-dev
  $0 -t      | build (or rebuild) theia; depends on theia-dev (-d)
  $0 -e      | build (or rebuild) theia-endpoint-runtime-binary; depends on dev and theia (-d -t)
  $0 --all   | equivalent to -d -t -e

Note that steps are run in the order specified, so always start with -d if needed.

Additional flags:
  --ctb      | CHE_THEIA_BRANCH from which to sync into CRW; default: ${SOURCE_BRANCH}
  --cb       | CRW_BRANCH from which to compute version of CRW to put in Dockerfiles, eg., devspaces-3.y-rhel-8 or ${MIDSTM_BRANCH}
  --cv       | rather than pull from CRW_BRANCH version of redhat-developer/devspaces/dependencies/VERSION file, 
             | just set CRW_VERSION; default: ${CRW_VERSION}
  --tb       | container build arg THEIA_BRANCH from which to get Eclipse Theia sources, default: ${THEIA_BRANCH} [never change this]
  --tgr      | container build arg THEIA_GITHUB_REPO from which to get Eclipse Theia sources, default: ${THEIA_GITHUB_REPO}
             | optional: redhat-developer/eclipse-theia - so we can build from a tag instead of a SHA
  --tcs      | container build arg THEIA_COMMIT_SHA from which commit SHA to get Eclipse Theia sources; default: ${THEIA_COMMIT_SHA}
             | if not set, extract from https://raw.githubusercontent.com/eclipse/che-theia/SOURCE_BRANCH/build.include
  --nv       | node version to use; default: ${nodeVersion}

Source control flags:
  --commit      | using GITHUB_TOKEN, commit updated content in dockerfiles/ folder

Docker + Podman flags:
  --no-images   | don't build images; just generate Dockerfiles
  --no-cache    | do not use docker/podman cache
  --rm-cache    | before building anything, purge target images from local docker/podman cache

Test control flags:
  --no-async-tests | replace test(...async...) with test.skip(...async...) in .ts test files
  --no-sync-tests  | replace test(...)         with test.skip(...) in .ts test files
  --no-tests       | skip both sync and async tests in .ts test files
  --pr             | if building based on a GH pull request, use 'pr' in tag names instead of 'tmp'
  --gh             | if building in GH action, use 'gh' in tag names instead of 'tmp'
  --ci             | if building in Jenkins, use 'ci' in tag names instead of 'tmp'

Cleanup options:
  --rmi:all | delete all generated images when done
  --rmi:tmp | delete temp images when done
"
  exit
}
if [[ $# -lt 1 ]] || [[ -z $GITHUB_TOKEN ]]; then usage; fi

# NOTE: SElinux needs to be permissive or disabled to volume mount a container to extract file(s)

STEPS=""
DELETE_TMP_IMAGES=0
DELETE_ALL_IMAGES=0
DELETE_CACHE_IMAGES=0
SKIP_ASYNC_TESTS=0
SKIP_SYNC_TESTS=0
DOCKERFLAGS="" # eg., --no-cache
DO_DOCKER_BUILDS=1 # by default generate dockerfiles and then build containers
COMMIT_CHANGES=0 # by default, don't commit anything that changed; optionally, use GITHUB_TOKEN to push changes to the current branch

for key in "$@"; do
  case $key in 
      '--nv') nodeVersion="$2"; shift 2;;
      '--ctb') SOURCE_BRANCH="$2"; shift 2;;
      '--tb') THEIA_BRANCH="$2"; shift 2;;
      '--tgr') THEIA_GITHUB_REPO="$2"; shift 2;;
      '--tcs') THEIA_COMMIT_SHA="$2"; shift 2;;
      '--cb')  MIDSTM_BRANCH="$2"; shift 2;;
      '--cv')  CRW_VERSION="$2"; shift 2;;
      '-d') STEPS="${STEPS} bootstrap_ds_theia_dev"; shift 1;;
      '-t') STEPS="${STEPS} bootstrap_ds_theia"; shift 1;;
      '-e'|'-b') STEPS="${STEPS} bootstrap_ds_theia_endpoint_runtime_binary"; shift 1;;
      '--all') STEPS="bootstrap_ds_theia_dev bootstrap_ds_theia bootstrap_ds_theia_endpoint_runtime_binary"; shift 1;;
      '--no-images') DO_DOCKER_BUILDS=0; shift 1;;
      '--no-cache') DOCKERFLAGS="${DOCKERFLAGS} $1"; shift 1;;
      '--rm-cache') DELETE_CACHE_IMAGES=1; shift 1;;
      '--rmi:tmp') DELETE_TMP_IMAGES=1; shift 1;;
      '--rmi:all') DELETE_ALL_IMAGES=1; shift 1;;
      '--no-async-tests') SKIP_ASYNC_TESTS=1; shift 1;;
      '--no-sync-tests')  SKIP_SYNC_TESTS=1; shift 1;;
      '--no-tests')       SKIP_ASYNC_TESTS=1; SKIP_SYNC_TESTS=1; shift 1;;
      '--commit')         COMMIT_CHANGES=1; shift 1;;
      '--pr') BUILD_TYPE="pr"; shift 1;;
      '--gh') BUILD_TYPE="gh"; shift 1;;
      '--ci') BUILD_TYPE="ci"; shift 1;; # TODO support using latest image tag or sha here 
      '-h'|'--help') usage; shift 1;;
  esac
done

if [[ ! ${CRW_VERSION} ]] && [[ ${MIDSTM_BRANCH} ]]; then
  CRW_VERSION=$(curl -sSLo- https://raw.githubusercontent.com/redhat-developer/devspaces/${MIDSTM_BRANCH}/dependencies/VERSION)
fi
if [[ ! ${CRW_VERSION} ]]; then 
  echo "Error: must set either --cb devspaces-3.y-rhel-8 or --cv 3.y to define the version of CRW Theia to build."
  usage
fi

BUILDER=$(command -v podman || true)
if [[ ! -x $BUILDER ]]; then
  # echo "[WARNING] podman is not installed, trying with docker"
  BUILDER=$(command -v docker || true)
  if [[ ! -x $BUILDER ]]; then
    echo "[ERROR] Neither podman nor docker is installed. Install it to continue."
    exit 1
  fi
fi

set -x

if [[ ! ${THEIA_COMMIT_SHA} ]]; then
  pushd /tmp >/dev/null || true
  curl -sSLO https://raw.githubusercontent.com/eclipse/che-theia/${SOURCE_BRANCH}/build.include
  export "$(cat build.include | grep -E "^THEIA_COMMIT_SHA")" && THEIA_COMMIT_SHA=${THEIA_COMMIT_SHA//\"/}
  popd >/dev/null || true
fi
echo "[INFO] Using Eclipse Theia commit SHA THEIA_COMMIT_SHA = ${THEIA_COMMIT_SHA}"

#need to edit conf/theia/ubi8-brew/builder-from.dockerfile file as well for now
#need to edit conf/theia-endpoint-runtime/ubi8-brew/builder-from.dockerfile file as well for now
UNAME="$(uname -m)"
CHE_THEIA_DEV_IMAGE_NAME="quay.io/devspaces/theia-dev-rhel8:${CRW_VERSION}-${UNAME}"
CHE_THEIA_IMAGE_NAME="quay.io/devspaces/theia-rhel8:${CRW_VERSION}-${UNAME}"
CHE_THEIA_ENDPOINT_BINARY_IMAGE_NAME="quay.io/devspaces/theia-endpoint-rhel8:${CRW_VERSION}-${UNAME}"

base_dir=$(cd "$(dirname "$0")"; pwd)

# variables
TMP_DIR=${base_dir}/tmp
BREW_DOCKERFILE_ROOT_DIR="${base_dir}/dockerfiles"
CHE_THEIA_DIR="${TMP_DIR}/che-theia"

TMP_THEIA_DEV_BUILDER_IMAGE="quay.io/devspaces/theia-dev-rhel8:${CRW_VERSION}-${BUILD_TYPE}-builder-${UNAME}"
TMP_THEIA_BUILDER_IMAGE="quay.io/devspaces/theia-rhel8:${CRW_VERSION}-${BUILD_TYPE}-builder-${UNAME}"
TMP_THEIA_RUNTIME_IMAGE="quay.io/devspaces/theia-rhel8:${CRW_VERSION}-${BUILD_TYPE}-runtime-${UNAME}"
TMP_THEIA_ENDPOINT_BINARY_BUILDER_IMAGE="quay.io/devspaces/theia-endpoint-rhel8:${CRW_VERSION}-${BUILD_TYPE}-builder-${UNAME}"

rmi_images() {
  set +x
  DELETE_CACHE=$1
  # optional cleanup of generated images
  if [[ ${DELETE_CACHE} -eq 1 ]] || [[ ${DELETE_TMP_IMAGES} -eq 1 ]] || [[ ${DELETE_ALL_IMAGES} -eq 1 ]]; then
    echo;echo "Delete temp images from container registry"
    ${BUILDER} rmi -f $TMP_THEIA_DEV_BUILDER_IMAGE $TMP_THEIA_BUILDER_IMAGE $TMP_THEIA_RUNTIME_IMAGE $TMP_THEIA_ENDPOINT_BINARY_BUILDER_IMAGE || true
  fi
  if [[ ${DELETE_CACHE} -eq 1 ]] || [[ ${DELETE_ALL_IMAGES} -eq 1 ]]; then
    echo;echo "Delete che-theia images from container registry"
    ${BUILDER} rmi -f $CHE_THEIA_DEV_IMAGE_NAME $CHE_THEIA_IMAGE_NAME $CHE_THEIA_ENDPOINT_BINARY_IMAGE_NAME || true
  fi
  set -x
}

# wipe local images from cache
if [[ ${DELETE_CACHE_IMAGES} -eq 1 ]]; then rmi_images 1; fi

# method to look for failures in build logs; over time we can add more strings to grep
findErrors() {
  # found a matching string
  findErrors_Out="$(grep -E "gyp ERR|error Command failed with exit code|error building at STEP" $1 || true)"
  if [[ $findErrors_Out ]]; then
    return 1
  else 
    return 0
  fi
}

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
  if [[ ${SOURCE_BRANCH} == *"@"* ]]; then # if the branch includes an @SHA suffix, use that SHA from the branch
    git clone -b "${SOURCE_BRANCH%%@*}" --single-branch https://github.com/eclipse-che/che-theia "${CHE_THEIA_DIR}"
    if [[ ! -d "${CHE_THEIA_DIR}" ]]; then echo "[ERR""OR] could not clone https://github.com/eclipse-che/che-theia from ${SOURCE_BRANCH%%@*} !"; exit 1; fi 
    pushd "${CHE_THEIA_DIR}" >/dev/null
      git reset "${SOURCE_BRANCH##*@}" --hard
      if [[ "$(git --no-pager log --pretty=format:'%Cred%h%Creset' --abbrev-commit -1)" != "${SOURCE_BRANCH##*@}" ]]; then 
        echo "[ERR""OR] could not find SHA ${SOURCE_BRANCH##*@} in branch ${SOURCE_BRANCH%%@*} !"; 
        echo "Latest 10 commits:"
        git --no-pager log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %C(blue)%aE%Creset %Cgreen(%cr)%Creset' --abbrev-commit -10
        echo
        exit 1
      fi
    popd >/dev/null
  else # clone from tag/branch
    git clone -b "${SOURCE_BRANCH}" --single-branch --depth 1 https://github.com/eclipse-che/che-theia "${CHE_THEIA_DIR}"
    if [[ ! -d "${CHE_THEIA_DIR}" ]]; then echo "[ERR""OR] could not clone https://github.com/eclipse-che/che-theia from ${SOURCE_BRANCH} !"; exit 1; fi 
  fi

  if [[ ${SKIP_ASYNC_TESTS} -eq 1 ]]; then
    set +e
    set +x
    for d in $(find ${CHE_THEIA_DIR} -type f -name "*.ts" | grep -E test); do
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
    for d in $(find ${CHE_THEIA_DIR} -type f -name "*.ts" | grep -E test); do
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

    # @since 2.15 CRW-2656 - these changes have been applied in che-theia, so don't need them in devspaces-theia
    # keeping comments for reference in case new dockerfile/package.json/yarn.lock changes break CRW, and we need to do testing/updates here

    # # @since 2.11 - CRW-2156 - use keytar 7.6 + node-addon-api in Eclipse Theia sources
    # sed_in_place dockerfiles/theia/Dockerfile -r \
    #   -e 's|"\*\*/keytar": "\^7.[0-9].0"|"\*\*/keytar": "7.6.0", \\n    "\*\*/node-addon-api": "3.1.0"|g'
    # grep -E "keytar|node-addon-api"  dockerfiles/theia/Dockerfile

    # # @since 2.15 - include both node-addon-api 1.7.2 and 3.1.0 in Che Theia sources
    # sed_in_place package.json -r \
    #   -e 's|node-addon-api": ".+",|node-addon-api": "1.7.2",|g' \
    #   -e '/ +"node-addon-api": .+/a \ \ \ \ "node-addon-api-latest": "npm:node-addon-api@3.1.0",'
    # grep -E "keytar|node-addon-api"  package.json
    # # remove lerna from resolutions as it's in devDependencies
    # jq -r 'del(.resolutions.lerna)' package.json > package.json1; mv package.json1 package.json

    # # @since 2.15 - replace keytar 7.x with 7.6 in Che Theia sources
    # sed_in_place ./generator/tests/init-sources/templates/theia-core-package.json -r \
    #   -e 's|"keytar": "7.[0-9].0"|"keytar": "7.6.0"|g'
    # grep -E "keytar|node-addon-api" ./generator/tests/init-sources/templates/theia-core-package.json

    # # @since 2.15 - replace keytar 7.x with 7.6; include both node-addon-api 1.7.2 and 3.1.0 in Che Theia sources
    # sed_in_place yarn.lock -r \
    #   -e 's|keytar "7.[0-9].0"|keytar "7.6.0"|' -e 's|keytar@\^7.[0-9].0|keytar@7.6.0|' -e 's|keytar@7.[0-9].0|keytar@7.6.0|' -e 's|version "7.7.0"|version "7.6.0"|' \
    #   -e 's|keytar@7.6.0, keytar@7.6.0|keytar@7.6.0|' \
    #   -e 's|keytar-.+.tgz#.+|keytar-7.6.0.tgz#498e796443cb543d31722099443f29d7b5c44100"|' \
    #   -e 's|sha512-YEY9HWqThQc5q5xbXbRwsZTh2PJ36OSYRjSv3NN2xf5s5dpLTjEZnC2YikR29OaVybf9nQ0dJ/80i40RS97t/A==|sha512-H3cvrTzWb11+iv0NOAnoNAPgEapVZnYLVHZQyxmh7jdmVfR/c0jNNFEZ6AI38W/4DeTGTaY66ZX4Z1SbfKPvCQ==|' \
    #   -e 's|node-addon-api "\^3.0.0"|node-addon-api "3.1.0"|g' \
    #   `# @since 2.15 - CRW-2656 remove entire node-addon-api block, which currently resolves to 4.0.0 (we want 3.1.0)` \
    #   -e '/node-addon-api@\*:/,+4d' \
    #   -e '/node-addon-api@^1.+:/,+4d' \
    #   -e '/node-addon-api@\^3.0.0/{n;d}';
    # sed_in_place yarn.lock -r \
    #   -e '/node-addon-api@\^3.0.0/a \ \ version "3.1.0"' \
    #   -e 's|node-addon-api@\^3.0.0|node-addon-api@3.1.0|g' \
    #   -e 's|node-addon-api-3.2.1.tgz#81325e0a2117789c0128dab65e7e38f07ceba161|node-addon-api-3.1.0.tgz#98b21931557466c6729e51cb77cd39c965f42239|g' \
    #   -e 's|sha512-mmcei9JghVNDYydghQmeDX8KoAm0FAiYyIcUt/N4nhyAipB17pllZQDOJD2fotxABnt4Mdz\+dKTO7eftLg4d0A==|sha512-flmrDNB06LIl5lywUz7YlNGZH/5p0M7W28k8hzd9Lshtdh1wshD2Y+U4h9LD6KObOy1f+fEVdgprPrEymjM5uw==|g'
    # grep -E "keytar|node-addon-api" yarn.lock
  popd >/dev/null

  # init yarn in che-theia
  pushd "${CHE_THEIA_DIR}" >/dev/null
  CHE_THEIA_SHA=$(git rev-parse --short=4 HEAD); echo "CHE_THEIA_SHA=${CHE_THEIA_SHA}"

  # Patch theiaPlugins.json to add vscode-commons as a built-in
  # See CRW-1894
  VSCODE_COMMONS="https://github.com/redhat-developer/devspaces-vscode-extensions/releases/download/v608e3a2/redhat.vscode-commons-021b0165bb5ba05e107ee7e31d1e59a7a73f473c.vsix"
  jq --arg location "$VSCODE_COMMONS" '. += {"vscode-commons": $location}' "${CHE_THEIA_DIR}/generator/src/templates/theiaPlugins.json" > "${TMP_DIR}/theiaPlugins.json"
  mv "${TMP_DIR}/theiaPlugins.json" "${CHE_THEIA_DIR}/generator/src/templates/theiaPlugins.json"

  # CRW-2600 debugging why there's a dependency on lerna 4
  yarn why lerna

  yarn --ignore-scripts
  popd >/dev/null
fi

mkdir -p "${BREW_DOCKERFILE_ROOT_DIR}"
DOCKERFILES_ROOT_DIR="${CHE_THEIA_DIR}/dockerfiles"

bootstrap_ds_theia_dev() {
  cd "${base_dir}"
  mkdir -p "${BREW_DOCKERFILE_ROOT_DIR}"/theia-dev

  # apply overrides from devspaces-theia
  if [[ -d conf/theia-dev/ubi8/ ]]; then cp conf/theia-dev/ubi8/* "${DOCKERFILES_ROOT_DIR}"/theia-dev/docker/ubi8/; fi
  # build only ubi8 image
  pushd "${DOCKERFILES_ROOT_DIR}"/theia-dev >/dev/null
  CMD="./build.sh --dockerfile:Dockerfile.ubi8 --skip-tests --dry-run \
    --build-args:GITHUB_TOKEN=${GITHUB_TOKEN}"
  echo $CMD; $CMD
  cp "${DOCKERFILES_ROOT_DIR}"/theia-dev/.Dockerfile "${BREW_DOCKERFILE_ROOT_DIR}"/theia-dev/bootstrap.Dockerfile

  if [[ ${DO_DOCKER_BUILDS} -eq 1 ]]; then 
    ${BUILDER} build -f .Dockerfile -t "${TMP_THEIA_DEV_BUILDER_IMAGE}" . ${DOCKERFLAGS} --build-arg GITHUB_TOKEN=${GITHUB_TOKEN}
    if [[ $? -ne 0 ]]; then echo "[ERROR] Container build of ${TMP_THEIA_DEV_BUILDER_IMAGE} failed." exit 1; fi

    # CRW-1609 - @since 2.9 - push temp image to quay (need it for assets and downstream container builds)
    ${BUILDER} push "${TMP_THEIA_DEV_BUILDER_IMAGE}"
    ${BUILDER} tag "${TMP_THEIA_DEV_BUILDER_IMAGE}" eclipse/che-theia-dev:next || true
  fi
  popd >/dev/null

  # Create image theia-dev:ubi8-brew
  rm -rf "${DOCKERFILES_ROOT_DIR}"/theia-dev/docker/ubi8-brew
  cp -r "${DOCKERFILES_ROOT_DIR}"/theia-dev/docker/ubi8 "${DOCKERFILES_ROOT_DIR}"/theia-dev/docker/ubi8-brew
  # Add extra conf
  cp conf/theia-dev/ubi8-brew/* "${DOCKERFILES_ROOT_DIR}"/theia-dev/docker/ubi8-brew/
  sed -E -e "s/@@CRW_VERSION@@/${CRW_VERSION}/g" -i "${DOCKERFILES_ROOT_DIR}"/theia-dev/docker/ubi8-brew/post-env.dockerfile

  # dry-run for theia-dev:ubi8-brew to only generate Dockerfile
  pushd "${DOCKERFILES_ROOT_DIR}"/theia-dev >/dev/null
  CMD="./build.sh --dockerfile:Dockerfile.ubi8-brew --skip-tests --dry-run \
    --build-args:GITHUB_TOKEN=${GITHUB_TOKEN}"
  echo $CMD; $CMD
  popd >/dev/null
  cp "${DOCKERFILES_ROOT_DIR}"/theia-dev/.Dockerfile "${BREW_DOCKERFILE_ROOT_DIR}"/theia-dev/rhel.Dockerfile

  # Copy assets from ubi8 to local
  pushd "${BREW_DOCKERFILE_ROOT_DIR}"/theia-dev >/dev/null
  echo "Remove previous assets"
  rm -rf assets-*
  # copy assets
  cp -r "${CHE_THEIA_DIR}"/dockerfiles/theia-dev/asset-* . && ls -la asset-*

  # copy DOCKERFILES_ROOT_DIR/theia-dev/src folder into BREW_DOCKERFILE_ROOT_DIR/theia-dev
  rm -fr theia-dev/src
  rsync -azrlt --checksum --delete "${DOCKERFILES_ROOT_DIR}"/theia-dev/src/* src/
  popd >/dev/null

  # echo "BEFORE SED ======= ${BREW_DOCKERFILE_ROOT_DIR}/theia-dev/Dockerfile =======>"
  # cat "${BREW_DOCKERFILE_ROOT_DIR}"/theia-dev/Dockerfile
  # echo "<======= ${BREW_DOCKERFILE_ROOT_DIR}/theia-dev/Dockerfile ======="

  # Copy generated Dockerfile, with Brew transformations
  sed -r "${DOCKERFILES_ROOT_DIR}"/theia-dev/.Dockerfile \
  `# cannot resolve RHCC from inside Brew so use no registry to resolve from Brew using same container name` \
  -e "s#FROM registry.redhat.io/#FROM #g" \
  -e "s#FROM registry.access.redhat.com/#FROM #g" \
  > "${BREW_DOCKERFILE_ROOT_DIR}"/theia-dev/Dockerfile

  # fix Dockerfile to use tarball instead of folder
  # -COPY asset-unpacked-generator ${HOME}/eclipse-che-theia-generator
  # +COPY asset-eclipse-che-theia-generator.tgz ${HOME}/eclipse-che-theia-generator.tgz
  # + RUN tar zxf eclipse-che-theia-generator.tgz && mv package eclipse-che-theia-generator
  newline='
'
  sed_in_place -e "s#COPY asset-unpacked-generator \${HOME}/eclipse-che-theia-generator#COPY asset-eclipse-che-theia-generator.tgz \${HOME}/eclipse-che-theia-generator.tgz\\${newline}RUN cd \${HOME} \&\& tar zxf eclipse-che-theia-generator.tgz \&\& mv package eclipse-che-theia-generator#" "${BREW_DOCKERFILE_ROOT_DIR}"/theia-dev/Dockerfile

  # echo "AFTER SED ======= ${BREW_DOCKERFILE_ROOT_DIR}/theia-dev/Dockerfile =======>"
  # cat "${BREW_DOCKERFILE_ROOT_DIR}"/theia-dev/Dockerfile
  # echo "<======= ${BREW_DOCKERFILE_ROOT_DIR}/theia-dev/Dockerfile ======="

  # TODO do we need to run this build ? isn't the above build good enough?
  # # build local
  # pushd "${BREW_DOCKERFILE_ROOT_DIR}"/theia-dev >/dev/null
  # ${BUILDER} build -t ${CHE_THEIA_DEV_IMAGE_NAME} . ${DOCKERFLAGS} --build-arg GITHUB_TOKEN=${GITHUB_TOKEN}
  # if [[ $? -ne 0 ]]; then echo "[ERROR] Container build of ${CHE_THEIA_DEV_IMAGE_NAME} failed." exit 1; fi
  # popd >/dev/null
  # # publish image to quay
  # ${BUILDER} push "${CHE_THEIA_DEV_IMAGE_NAME}"

  # # echo generated Dockerfiles
  # pushd "${BREW_DOCKERFILE_ROOT_DIR}"/theia-dev >/dev/null
  # while IFS= read -r -d '' d; do
  #   echo "==== ${d} ====>"
  #   cat $d
  #   echo "<====  ${d} ===="
  # done <   <(find . -type f -regextype posix-extended -iregex '.+(Dockerfile).*' -print0)
  # popd >/dev/null
} # end bootstrap_ds_theia_dev

# now do che-theia
bootstrap_ds_theia() {
  # pull the temp image from quay so we can use it in this build, but rename it because che-theia hardcodes image dependencies
  ${BUILDER} pull "${TMP_THEIA_DEV_BUILDER_IMAGE}"
  ${BUILDER} tag "${TMP_THEIA_DEV_BUILDER_IMAGE}" eclipse/che-theia-dev:next || true

  cd "${base_dir}"
  mkdir -p "${BREW_DOCKERFILE_ROOT_DIR}"/theia

  # apply overrides from devspaces-theia
  if [[ -d conf/theia/ubi8/ ]]; then cp conf/theia/ubi8/* "${DOCKERFILES_ROOT_DIR}"/theia/docker/ubi8/; fi
  # build only ubi8 image and for target builder first, so we can extract data
  pushd "${DOCKERFILES_ROOT_DIR}"/theia >/dev/null
  # first generate the Dockerfile
  CMD="./build.sh --dockerfile:Dockerfile.ubi8 --skip-tests --dry-run --tag:next --branch:${THEIA_BRANCH} --target:builder \
    --build-args:GITHUB_TOKEN=${GITHUB_TOKEN},DO_REMOTE_CHECK=false,DO_CLEANUP=false,THEIA_GITHUB_REPO=${THEIA_GITHUB_REPO},THEIA_COMMIT_SHA=${THEIA_COMMIT_SHA}"
  echo $CMD; $CMD
  # CRW-2600 patch with why lerna
  sed_in_place "${DOCKERFILES_ROOT_DIR}"/theia/.Dockerfile -r -e "s#(yarn .+ yarn build)#yarn why lerna \&\& \1#"

  cp "${DOCKERFILES_ROOT_DIR}"/theia/.Dockerfile "${BREW_DOCKERFILE_ROOT_DIR}"/theia/bootstrap.Dockerfile
  cp "${DOCKERFILES_ROOT_DIR}"/theia/.Dockerfile "${DOCKERFILES_ROOT_DIR}"/theia/.ubi8-dockerfile

  if [[ ${DO_DOCKER_BUILDS} -eq 1 ]]; then 
    # Create one image for builder
    ${BUILDER} build -f "${DOCKERFILES_ROOT_DIR}"/theia/.ubi8-dockerfile -t ${TMP_THEIA_BUILDER_IMAGE} --target builder . ${DOCKERFLAGS} \
      --build-arg GITHUB_TOKEN=${GITHUB_TOKEN} --build-arg THEIA_GITHUB_REPO=${THEIA_GITHUB_REPO} \
      --build-arg THEIA_COMMIT_SHA=${THEIA_COMMIT_SHA} \
      | tee /tmp/TMP_THEIA_BUILDER_IMAGE.log.txt; findErrors /tmp/TMP_THEIA_BUILDER_IMAGE.log.txt
    if [[ $? -ne 0 ]]; then 
      echo "============================================================="
      echo "[ERROR] Container build of ${TMP_THEIA_BUILDER_IMAGE} failed."
      echo $findErrors_Out
      echo "============================================================="
      exit 1
    fi
    echo "Build [1/2] of ${TMP_THEIA_BUILDER_IMAGE} complete on $(uname -m). Begin pushing container to quay..."
    ${BUILDER} push "${TMP_THEIA_BUILDER_IMAGE}" 

    # and create runtime image as well
    ${BUILDER} build -f .ubi8-dockerfile -t ${TMP_THEIA_RUNTIME_IMAGE} . ${DOCKERFLAGS} \
      --build-arg GITHUB_TOKEN=${GITHUB_TOKEN} --build-arg THEIA_GITHUB_REPO=${THEIA_GITHUB_REPO} \
      --build-arg THEIA_COMMIT_SHA=${THEIA_COMMIT_SHA} \
      | tee /tmp/TMP_THEIA_RUNTIME_IMAGE.log.txt; findErrors /tmp/TMP_THEIA_RUNTIME_IMAGE.log.txt
    if [[ $? -ne 0 ]]; then 
      echo "============================================================="
      echo "[ERROR] Container build of ${TMP_THEIA_RUNTIME_IMAGE} failed." 
      echo $findErrors_Out
      echo "============================================================="
      exit 1 
    fi

    echo "Build [2/2] of ${TMP_THEIA_RUNTIME_IMAGE} complete on $(uname -m). Begin pushing container to quay..."
    # CRW-1609 - @since 2.9 - push temp image to quay (need it for assets and downstream container builds)
    ${BUILDER} push "${TMP_THEIA_RUNTIME_IMAGE}" 
    ${BUILDER} tag "${TMP_THEIA_RUNTIME_IMAGE}" eclipse/che-theia:next || true
  fi
  popd >/dev/null
  
  # Create image theia-dev:ubi8-brew
  rm -rf "${DOCKERFILES_ROOT_DIR}"/theia/docker/ubi8-brew
  cp -r "${DOCKERFILES_ROOT_DIR}"/theia/docker/ubi8 "${DOCKERFILES_ROOT_DIR}"/theia/docker/ubi8-brew
  # Add extra conf
  cp conf/theia/ubi8-brew/* "${DOCKERFILES_ROOT_DIR}"/theia/docker/ubi8-brew/
  sed -E -e "s/@@CRW_VERSION@@/${CRW_VERSION}/g" -i "${DOCKERFILES_ROOT_DIR}"/theia/docker/ubi8-brew/runtime-post-env.dockerfile

  # dry-run for theia:ubi8-brew to only generate Dockerfile
  pushd "${DOCKERFILES_ROOT_DIR}"/theia >/dev/null
  CMD="./build.sh --dockerfile:Dockerfile.ubi8-brew --skip-tests --dry-run --tag:next --branch:${THEIA_BRANCH} --target:builder \
    --build-args:GITHUB_TOKEN=${GITHUB_TOKEN},DO_REMOTE_CHECK=false,THEIA_GITHUB_REPO=${THEIA_GITHUB_REPO},THEIA_COMMIT_SHA=${THEIA_COMMIT_SHA}"
  echo $CMD; $CMD
  cp "${DOCKERFILES_ROOT_DIR}"/theia/.Dockerfile "${BREW_DOCKERFILE_ROOT_DIR}"/theia/rhel.Dockerfile
  popd >/dev/null

  # Copy assets from ubi8 to local
  pushd "${BREW_DOCKERFILE_ROOT_DIR}"/theia >/dev/null

  # copy assets
  cp "${CHE_THEIA_DIR}"/dockerfiles/theia/asset-* .

  # copy DOCKERFILES_ROOT_DIR/theia/src folder into BREW_DOCKERFILE_ROOT_DIR/theia
  rm -fr theia/src
  rsync -azrlt --checksum --delete "${DOCKERFILES_ROOT_DIR}"/theia/src/* src/

  # Copy generated Dockerfile, with Brew transformations
  sed -r "${DOCKERFILES_ROOT_DIR}"/theia/.Dockerfile \
  `# cannot resolve RHCC from inside Brew so use no registry to resolve from Brew using same container name` \
  -e "s#FROM registry.redhat.io/#FROM #g" \
  -e "s#FROM registry.access.redhat.com/#FROM #g" \
  `# cannot resolve quay from inside Brew so use internal mirror w/ revised container name` \
  -e "s#quay.io/devspaces/#registry-proxy.engineering.redhat.com/rh-osbs/devspaces-#g" \
  `# cannot resolve theia-rhel8:next, theia-dev-rhel8:next from inside Brew so use revised container tag` \
  -e "s#(theia-.+):next#\1:${CRW_VERSION}#g" \
  > "${BREW_DOCKERFILE_ROOT_DIR}"/theia/Dockerfile

  # echo "========= ${BREW_DOCKERFILE_ROOT_DIR}/theia/Dockerfile =========>"
  # cat "${BREW_DOCKERFILE_ROOT_DIR}"/theia/Dockerfile
  # echo "<========= ${BREW_DOCKERFILE_ROOT_DIR}/theia/Dockerfile ========="

  popd >/dev/null

  # TODO do we need to run this build ? isn't the above build good enough?
  # # build local
  # # https://github.com/eclipse/che/issues/16844 -- fails in Jenkins and locally since 7.12 so comment out 
  # pushd "${BREW_DOCKERFILE_ROOT_DIR}"/theia >/dev/null
  # ${BUILDER} build -t ${CHE_THEIA_IMAGE_NAME} . ${DOCKERFLAGS} \
  #  --build-arg GITHUB_TOKEN=${GITHUB_TOKEN} --build-arg THEIA_GITHUB_REPO=${THEIA_GITHUB_REPO} --build-arg THEIA_COMMIT_SHA=${THEIA_COMMIT_SHA} \
  #  2>&1 | tee /tmp/CHE_THEIA_IMAGE_NAME_buildlog.txt
  # # NONZERO="$(grep -E "a non-zero code:|Exit code: 1|Command failed"  /tmp/CHE_THEIA_IMAGE_NAME_buildlog.txt || true)"
  # # if [[ $? -ne 0 ]] || [[ $NONZERO ]]; then 
  # #  echo "[ERROR] Container build of ${CHE_THEIA_IMAGE_NAME} failed: "
  # #  echo "${NONZERO}"
  # #  exit 1
  # # fi
  # popd >/dev/null
  # ${BUILDER} push "${CHE_THEIA_IMAGE_NAME}"

  # Set the CDN options inside the Dockerfile
  sed_in_place -r -e 's#ARG CDN_PREFIX=.+#ARG CDN_PREFIX="https://static.developers.redhat.com/che/ds_theia_artifacts/"#' "${BREW_DOCKERFILE_ROOT_DIR}"/theia/Dockerfile
  sed_in_place -r -e 's#ARG MONACO_CDN_PREFIX=.+#ARG MONACO_CDN_PREFIX="https://cdn.jsdelivr.net/npm/"#' "${BREW_DOCKERFILE_ROOT_DIR}"/theia/Dockerfile

  sed_in_place -r \
  `# fix up theia loader patch inclusion (3 steps)` \
  -e "s#ADD branding/loader/loader.patch .+#COPY asset-branding.tar.gz /tmp/asset-branding.tar.gz#g" \
  -e "s#ADD (branding/loader/loader.svg .+)#RUN tar xvzf /tmp/asset-branding.tar.gz -C /tmp; cp /tmp/\\1#g" \
  -e "s#(RUN cd .+/theia-source-code && git apply).+#\1 /tmp/branding/loader/loader.patch#g" \
  `# don't create tarballs` \
  -e "s#.+tar zcf.+##g" \
  `# don't do node-gyp installs, etc.` \
  -e "s#.+node-gyp.+##g" \
  `# copy from builder` \
  -e "s#^COPY branding #COPY --from=builder /tmp/branding #g" \
  `# replace lerna 2 with lerna 4` \
  `#-e 's#(lerna": ")2[^"]+"#\1>=4.0.0"#'` \
  "${BREW_DOCKERFILE_ROOT_DIR}"/theia/Dockerfile

  # verify that CDN is enabled
  grep -E "https://static.developers.redhat.com/che/ds_theia_artifacts/" "${BREW_DOCKERFILE_ROOT_DIR}"/theia/Dockerfile || exit 1
  grep -E "https://cdn.jsdelivr.net/npm/" "${BREW_DOCKERFILE_ROOT_DIR}"/theia/Dockerfile || exit 1

  # echo "-=-=-=- dockerfiles -=-=-=->"
  # find "${DOCKERFILES_ROOT_DIR}"/ -name "*ockerfile*" | grep -E -v "alpine|e2e"
  # echo "<-=-=-=- dockerfiles -=-=-=-"

  # # echo generated Dockerfiles
  # pushd "${BREW_DOCKERFILE_ROOT_DIR}"/theia >/dev/null
  # while IFS= read -r -d '' d; do
  #   echo "==== ${d} ====>"
  #   cat $d
  #   echo "<====  ${d} ===="
  # done <   <(find . -type f -regextype posix-extended -iregex '.+(Dockerfile).*' -print0)
  # popd >/dev/null
} # end bootstrap_ds_theia

# now do che-theia-endpoint-runtime-binary
bootstrap_ds_theia_endpoint_runtime_binary() {
  # pull the temp image from quay so we can use it in this build, but rename it because che-theia endpoint hardcodes image dependencies
  ${BUILDER} pull "${TMP_THEIA_RUNTIME_IMAGE}"
  ${BUILDER} tag "${TMP_THEIA_RUNTIME_IMAGE}" eclipse/che-theia:next || true
  # ${BUILDER} tag "${TMP_THEIA_RUNTIME_IMAGE}" "${CHE_THEIA_IMAGE_NAME}" || true # maybe not needed?

  # revert any local changes to builder-from.dockerfile
  pushd "${DOCKERFILES_ROOT_DIR}"/theia-endpoint-runtime-binary/docker/ubi8 >/dev/null || exit 1
    git checkout builder-from.dockerfile >/dev/null || true
  popd >/dev/null || exit 1

  # pull or build che-custom-nodejs-deasync, using definition in:
  # https://github.com/eclipse/che-theia/blob/master/dockerfiles/theia-endpoint-runtime-binary/docker/ubi8/builder-from.dockerfile#L1
  if [[ ${DO_DOCKER_BUILDS} -eq 1 ]]; then 
    nodeRepoWithTag=$(grep -E 'FROM .*che-custom-nodejs-deasync.*' "${DOCKERFILES_ROOT_DIR}"/theia-endpoint-runtime-binary/docker/ubi8/builder-from.dockerfile  | cut -d' ' -f2)
    { ${BUILDER} pull ${nodeRepoWithTag}; rc=$?; } || true
    if [[ $rc -ne 0 ]] ; then # build if not available for current arch
      # clone che-custom-nodejs-deasync only if we need to build it
      git clone -b "master" --single-branch https://github.com/che-dockerfiles/che-custom-nodejs-deasync.git "${TMP_DIR}"/che-custom-nodejs-deasync
      if [[ ! -d "${TMP_DIR}"/che-custom-nodejs-deasync ]]; then echo "[ERR""OR] could not clone https://github.com/che-dockerfiles/che-custom-nodejs-deasync.git !"; exit 1; fi

      cd "${TMP_DIR}"/che-custom-nodejs-deasync
      nodeVersionDeAsync=$(grep -E 'FROM .*che-custom-nodejs-deasync.*' "${DOCKERFILES_ROOT_DIR}"/theia-endpoint-runtime-binary/docker/ubi8/builder-from.dockerfile  | cut -d' ' -f2 | cut -d':' -f2) # eg., 14.18.2
      echo "$nodeVersionDeAsync" > VERSION
      # TODO https://issues.redhat.com/browse/CRW-1215 this should be a UBI or scratch based build, not alpine
      # see https://github.com/che-dockerfiles/che-custom-nodejs-deasync/blob/master/Dockerfile#L12
      ${BUILDER} build -f Dockerfile -t ${nodeRepoWithTag} . ${DOCKERFLAGS} \
        --build-arg NODE_VERSION=${nodeVersionDeAsync}
    fi
  fi

  cd "${base_dir}"
  mkdir -p "${BREW_DOCKERFILE_ROOT_DIR}"/theia-endpoint-runtime-binary

  # @since 2.12 CRW-1731
  pushd "${BREW_DOCKERFILE_ROOT_DIR}"/theia-endpoint-runtime-binary >/dev/null
  # copy DOCKERFILES_ROOT_DIR/theia-endpoint-runtime-binary/src folder into BREW_DOCKERFILE_ROOT_DIR/theia-endpoint-runtime-binary
  rm -fr theia-endpoint-runtime-binary/src
  rsync -azrlt --checksum --delete "${DOCKERFILES_ROOT_DIR}"/theia-endpoint-runtime-binary/src/* src/
  popd >/dev/null

  # apply overrides from devspaces-theia
  if [[ -d conf/theia-endpoint-runtime-binary/ubi8/ ]]; then cp conf/theia-endpoint-runtime-binary/ubi8/* "${DOCKERFILES_ROOT_DIR}"/theia-endpoint-runtime-binary/docker/ubi8/; fi
  # build only ubi8 image and for target builder first, so we can extract data
  pushd "${DOCKERFILES_ROOT_DIR}"/theia-endpoint-runtime-binary >/dev/null
  # first generate the Dockerfile
  CMD="./build.sh --dockerfile:Dockerfile.ubi8 --skip-tests --dry-run --tag:next --target:builder \
    --build-args:GITHUB_TOKEN=${GITHUB_TOKEN},DO_REMOTE_CHECK=false"
  echo $CMD; $CMD
  cp "${DOCKERFILES_ROOT_DIR}"/theia-endpoint-runtime-binary/.Dockerfile "${BREW_DOCKERFILE_ROOT_DIR}"/theia-endpoint-runtime-binary/bootstrap.Dockerfile
  # keep a copy of the file
  cp .Dockerfile .ubi8-dockerfile
  # Create one image for builder target
  if [[ ${DO_DOCKER_BUILDS} -eq 1 ]]; then 
    ${BUILDER} build -f .ubi8-dockerfile -t ${TMP_THEIA_ENDPOINT_BINARY_BUILDER_IMAGE} --target builder . ${DOCKERFLAGS} \
      --build-arg GITHUB_TOKEN=${GITHUB_TOKEN}
    if [[ $? -ne 0 ]]; then echo "[ERROR] Container build of ${TMP_THEIA_ENDPOINT_BINARY_BUILDER_IMAGE} failed." exit 1; fi
    # CRW-1609 - @since 2.9 - push temp image to quay (need it for assets and downstream container builds)
    ${BUILDER} push "${TMP_THEIA_ENDPOINT_BINARY_BUILDER_IMAGE}" 
  fi
  popd >/dev/null

  # Create image theia-endpoint-runtime-binary:ubi8-brew
  rm -rf "${DOCKERFILES_ROOT_DIR}"/theia-endpoint-runtime-binary/docker/ubi8-brew
  cp -r "${DOCKERFILES_ROOT_DIR}"/theia-endpoint-runtime-binary/docker/ubi8 "${DOCKERFILES_ROOT_DIR}"/theia-endpoint-runtime-binary/docker/ubi8-brew

  # Add extra conf
  cp conf/theia-endpoint-runtime-binary/ubi8-brew/* "${DOCKERFILES_ROOT_DIR}"/theia-endpoint-runtime-binary/docker/ubi8-brew/
  sed -E -e "s/@@CRW_VERSION@@/${CRW_VERSION}/g" -i "${DOCKERFILES_ROOT_DIR}"/theia-endpoint-runtime-binary/docker/ubi8-brew/runtime-post-env.dockerfile

  # dry-run for theia-endpoint-runtime:ubi8-brew to only generate Dockerfile
  pushd "${DOCKERFILES_ROOT_DIR}"/theia-endpoint-runtime-binary >/dev/null
  CMD="./build.sh --dockerfile:Dockerfile.ubi8-brew --skip-tests --dry-run --tag:next --target:builder \
    --build-args:GITHUB_TOKEN=${GITHUB_TOKEN},DO_REMOTE_CHECK=false"
  echo $CMD; $CMD
  popd >/dev/null
  cp "${DOCKERFILES_ROOT_DIR}"/theia-endpoint-runtime-binary/.Dockerfile "${BREW_DOCKERFILE_ROOT_DIR}"/theia-endpoint-runtime-binary/rhel.Dockerfile

  # Copy generated Dockerfile, with Brew transformations
  sed -r "${DOCKERFILES_ROOT_DIR}"/theia-endpoint-runtime-binary/.Dockerfile \
  `# cannot resolve RHCC from inside Brew so use no registry to resolve from Brew using same container name` \
  -e "s#FROM registry.redhat.io/#FROM #g" \
  -e "s#FROM registry.access.redhat.com/#FROM #g" \
  `# cannot resolve quay from inside Brew so use internal mirror w/ revised container name` \
  -e "s#quay.io/devspaces/#registry-proxy.engineering.redhat.com/rh-osbs/devspaces-#g" \
  `# cannot resolve theia-rhel8:next, theia-dev-rhel8:next from inside Brew so use revised container tag` \
  -e "s#(theia-.+):next#\1:${CRW_VERSION}#g" \
  > "${BREW_DOCKERFILE_ROOT_DIR}"/theia-endpoint-runtime-binary/Dockerfile

  # TODO do we need to run this build ? isn't the above build good enough?
  # pushd "${BREW_DOCKERFILE_ROOT_DIR}"/theia-endpoint-runtime-binary >/dev/null
  # # build local
  # ${BUILDER} build -t ${CHE_THEIA_ENDPOINT_BINARY_IMAGE_NAME} . ${DOCKERFLAGS} \
  #   --build-arg GITHUB_TOKEN=${GITHUB_TOKEN} --build-arg THEIA_GITHUB_REPO=${THEIA_GITHUB_REPO} --build-arg THEIA_COMMIT_SHA=${THEIA_COMMIT_SHA}
  # if [[ $? -ne 0 ]]; then echo "[ERROR] Container build of ${CHE_THEIA_ENDPOINT_BINARY_IMAGE_NAME} failed." exit 1; fi
  # popd >/dev/null

  # # echo generated Dockerfiles
  # pushd "${BREW_DOCKERFILE_ROOT_DIR}"/theia-endpoint-runtime-binary >/dev/null
  # while IFS= read -r -d '' d; do
  #   echo "==== ${d} ====>"
  #   cat $d
  #   echo "<====  ${d} ===="
  # done <   <(find . -type f -regextype posix-extended -iregex '.+(Dockerfile).*' -print0)
  # popd >/dev/null
} # end bootstrap_ds_theia_endpoint_runtime_binary

for step in $STEPS; do
  echo 
  echo "=========================================================="
  echo "====== $step"
  echo "=========================================================="
  $step
done

rmi_images 0

set -x
if [[ $STEPS ]]; then 
  echo; echo "Dockerfiles and resources generated - for tarballs, use collect-assets.sh script. See the following folder(s) for content to upload to pkgs.devel.redhat.com:"
  for step in $STEPS; do
    output_dir=${step//_/-};output_dir=${output_dir/bootstrap-ds-/}
    echo " - ${BREW_DOCKERFILE_ROOT_DIR}/${output_dir}"
  done

  # commit changed files to this repo
  if [[ ${COMMIT_CHANGES} -eq 1 ]]; then
    pushd "${BREW_DOCKERFILE_ROOT_DIR}" >/dev/null
    git update-index --refresh || true  # ignore timestamp updates
    if [[ $(git diff-index HEAD --) ]]; then # file changed
      git add .
      echo "[INFO] Commit generated dockerfiles, lock files for these builds: ${STEPS//bootstrap_ds_/}"
      git commit -s -m "chore: generated dockerfiles, lock files"
      git pull || true
      git push || true
    fi
    popd >/dev/null
  fi
  echo
else
  echo; echo "Nothing to do! No build flags provided (-d, -t, -e, or --all). Run this script with -h for help."
fi