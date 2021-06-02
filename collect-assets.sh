#!/bin/bash
# Copyright (c) 2019-2021 Red Hat, Inc.
# This program and the accompanying materials are made
# available under the terms of the Eclipse Public License 2.0
# which is available at https://www.eclipse.org/legal/epl-2.0/
#
# SPDX-License-Identifier: EPL-2.0
#
# Contributors:
#   Red Hat, Inc. - initial API and implementation

# script to collect assets from theia-dev, theia, and theia-endpoint builder + runtime container images
# create tarballs & other files from those containers, which can then be committed to pkgs.devel repo

nodeVersion="12.21.0" # version of node to use for theia containers (aligned to version in ubi base images)

BUILD_TYPE="tmp" # use "tmp" prefix for temporary build tags in Quay, but if we're building based on a PR, set "pr" prefix

base_dir="$(pwd)"
BREW_DOCKERFILE_ROOT_DIR=${base_dir}/"dockerfiles"

STEPS=""
DELETE_TMP_IMAGES=0
CRW_VERSION=2.y

usage () {
  echo "Usage:
  $0 --cv CRW_VERSION [options]

Examples:
  $0 --cv 2.y --all --rmi:tmp

Options:
  $0 -d      | collect assets for theia-dev
  $0 -t      | collect assets for theia
  $0 -b      | collect assets for theia-endpoint-runtime-binary
  $0 --all   | equivalent to -d -t -b

Optional flags:
  --nv           | node version to use; default: ${nodeVersion}
  --podman       | detect podman and use that instead of docker for building, running, tagging + deleting containers
  --pull-request | if building based on a pull request, use 'pr' in tag names instead of 'tmp'
  --rmi:tmp      | delete temp images when done"
  exit
}
if [[ $# -lt 1 ]]; then usage; fi

for key in "$@"; do
  case $key in 
      '--nv') nodeVersion="$2"; shift 2;;
      '--cv')  CRW_VERSION="$2"; shift 2;;
      '-d') STEPS="${STEPS} collect_assets_crw_theia_dev"; shift 1;;
      '-t') STEPS="${STEPS} collect_assets_crw_theia"; shift 1;;
      '-b') STEPS="${STEPS} collect_assets_crw_theia_endpoint_runtime_binary"; shift 1;;
      '--all') STEPS="collect_assets_crw_theia_dev collect_assets_crw_theia collect_assets_crw_theia_endpoint_runtime_binary"; shift 1;;
      '--rmi:tmp') DELETE_TMP_IMAGES=1; shift 1;;
      '--podman')         PODMAN=$(which podman 2>/dev/null || true); shift 1;;
      '--podmanflags')    PODMANFLAGS="$2"; shift 2;;
      '--pull-request')   BUILD_TYPE="pr"; shift 1;;
  esac
done
echo "CRW_VERSION = ${CRW_VERSION}"
if [[ ${CRW_VERSION} == "2.y" ]]; then usage; fi

UNAME="$(uname -m)"
TMP_THEIA_DEV_BUILDER_IMAGE="quay.io/crw/theia-dev-rhel8:${CRW_VERSION}-${BUILD_TYPE}-builder-${UNAME}"
TMP_THEIA_BUILDER_IMAGE="quay.io/crw/theia-rhel8:${CRW_VERSION}-${BUILD_TYPE}-builder-${UNAME}"
TMP_THEIA_RUNTIME_IMAGE="quay.io/crw/theia-rhel8:${CRW_VERSION}-${BUILD_TYPE}-runtime-${UNAME}"
TMP_THEIA_ENDPOINT_BINARY_BUILDER_IMAGE="quay.io/crw/theia-endpoint-rhel8:${CRW_VERSION}-${BUILD_TYPE}-builder-${UNAME}"

# to build with podman if present, use --podman flag, else use docker
if [[ ${PODMAN} ]]; then
  DOCKERRUN="${PODMAN} run ${PODMANFLAGS}" # add quiet mode with "--podmanflags -q"
else
  DOCKERRUN="docker run"
fi

listAssets() {
  find "$1/" -name "asset*" -type f -a -not -name "asset-list-${UNAME}.txt" | sort -u | sed -r -e "s#^$1/*##" | tee "$1/asset-list-${UNAME}.txt"
  if [[ ! $(cat "$1/asset-list-${UNAME}.txt") ]]; then
    echo "[ERROR] Missing expected files in $1 - build must exit!"
    exit 1
  fi
}

createYarnAsset() {
  # Create asset with yarn cache, for a given container image
  # /usr/local/share/.cache/yarn/v*/ = yarn cache dir
  # /home/theia-dev/.yarn-global = yarn
  # /opt/app-root/src/.npm-global = yarn symlinks
  # ${DOCKERRUN} --rm --entrypoint sh ${TMP_THEIA_DEV_BUILDER_IMAGE} -c 'ls -la \
  #   /usr/local/share/.cache/yarn/v*/ \
  #   /home/theia-dev/.yarn-global \
  #   /opt/app-root/src/.npm-global'
  ${DOCKERRUN} --rm --entrypoint sh "${1}" -c 'tar -pzcf - \
    /usr/local/share/.cache/yarn/v*/ \
    /home/theia-dev/.yarn-global \
    /opt/app-root/src/.npm-global' > asset-yarn-"$(uname -m)".tgz
}

########################### theia-dev

collect_assets_crw_theia_dev() {
  mkdir -p "${BREW_DOCKERFILE_ROOT_DIR}"/theia-dev && \
  pushd "${BREW_DOCKERFILE_ROOT_DIR}"/theia-dev >/dev/null || exit 1

  createYarnAsset "${TMP_THEIA_DEV_BUILDER_IMAGE}"

  popd >/dev/null || exit 1
  listAssets "${BREW_DOCKERFILE_ROOT_DIR}"/theia-dev
}

########################### theia

collect_assets_crw_theia() {
  mkdir -p "${BREW_DOCKERFILE_ROOT_DIR}"/theia && \
  pushd "${BREW_DOCKERFILE_ROOT_DIR}"/theia >/dev/null || exit 1

  createYarnAsset "${TMP_THEIA_BUILDER_IMAGE}"

  # post-install dependencies
  # /home/theia-dev/theia-source-code/packages/debug-nodejs/download = node debug vscode binary
  # /home/theia-dev/theia-source-code/plugins/ = VS Code extensions
  # /tmp/vscode-ripgrep-cache-1.2.4 /tmp/vscode-ripgrep-cache-1.5.7 = rigrep binaries
  # /home/theia-dev/.cache = include electron/node-gyp cache
  # ${DOCKERRUN} --rm --entrypoint sh ${TMP_THEIA_BUILDER_IMAGE} -c 'ls -la \
  #   /home/theia-dev/theia-source-code/dev-packages \
  #   /home/theia-dev/theia-source-code/packages \
  #   /home/theia-dev/theia-source-code/plugins \
  #   /tmp/vscode-ripgrep-cache* \
  #   /home/theia-dev/.cache'
  ${DOCKERRUN} --rm --entrypoint sh ${TMP_THEIA_BUILDER_IMAGE} -c 'tar -pzcf - \
    /home/theia-dev/theia-source-code/dev-packages \
    /home/theia-dev/theia-source-code/packages \
    /home/theia-dev/theia-source-code/plugins \
    /tmp/vscode-ripgrep-cache-* \
    /home/theia-dev/.cache' > asset-post-download-dependencies-"$(uname -m)".tar.gz

  # node-headers
  download_url="https://nodejs.org/download/release/v${nodeVersion}/node-v${nodeVersion}-headers.tar.gz"
  echo -n "Local node version: "; node --version
  echo "Requested node version: v${nodeVersion}"
  echo "URL to curl: ${download_url}"
  curl -sSL "${download_url}" -o asset-node-headers.tar.gz
  # ${DOCKERRUN} --rm --entrypoint sh ${TMP_THEIA_BUILDER_IMAGE} -c 'nodeVersion=$(node --version); \
  # download_url="https://nodejs.org/download/release/${nodeVersion}/node-${nodeVersion}-headers.tar.gz" && curl ${download_url}' > asset-node-headers.tar.gz

  # Add yarn.lock after compilation
  ${DOCKERRUN} --rm --entrypoint sh ${TMP_THEIA_BUILDER_IMAGE} -c 'cat /home/theia-dev/theia-source-code/yarn.lock' > asset-yarn-"$(uname -m)".lock

  # Theia source code
  ${DOCKERRUN} --rm --entrypoint sh ${TMP_THEIA_BUILDER_IMAGE} -c 'cat /home/theia-dev/theia-source-code.tgz' > asset-theia-source-code.tar.gz

  # npm/yarn cache
  # /usr/local/share/.cache/yarn/v*/ = yarn cache dir
  # /opt/app-root/src/.npm-global = npm global
  # ${DOCKERRUN} --rm --entrypoint sh ${TMP_THEIA_RUNTIME_IMAGE} -c 'ls -la \
  #   /usr/local/share/.cache/yarn/v*/ \
  #   /opt/app-root/src/.npm-global'
  ${DOCKERRUN} --rm --entrypoint sh ${TMP_THEIA_RUNTIME_IMAGE} -c 'tar -pzcf - \
    /usr/local/share/.cache/yarn/v*/ \
    /opt/app-root/src/.npm-global' > asset-yarn-runtime-image-"$(uname -m)".tar.gz

  # Save sshpass sources
  ${DOCKERRUN} --rm --entrypoint sh ${TMP_THEIA_RUNTIME_IMAGE} -c 'cat /opt/app-root/src/sshpass.tar.gz' > asset-sshpass-sources.tar.gz

  # create asset-branding.tar.gz from branding folder contents
  # TODO need to fetch sources for this ?
  tar -pcvzf asset-branding.tar.gz branding/*

  popd >/dev/null || exit 1
  listAssets "${BREW_DOCKERFILE_ROOT_DIR}"/theia
}

########################### theia-endpoint

collect_assets_crw_theia_endpoint_runtime_binary() {
  mkdir -p "${BREW_DOCKERFILE_ROOT_DIR}"/theia-endpoint-runtime-binary && \
  pushd "${BREW_DOCKERFILE_ROOT_DIR}"/theia-endpoint-runtime-binary >/dev/null || exit 1

  # npm/yarn cache
  # /usr/local/share/.cache/yarn/v*/ = yarn cache dir
  # /usr/local/share/.config/yarn/global
  # /opt/app-root/src/.npm-global = yarn symlinks
  # ${DOCKERRUN} --rm --entrypoint sh ${TMP_THEIA_ENDPOINT_BINARY_BUILDER_IMAGE} -c 'ls -la \
  #   /usr/local/share/.cache/yarn/v*/ \
  #   /usr/local/share/.config/yarn/global'
  ${DOCKERRUN} --rm --entrypoint sh ${TMP_THEIA_ENDPOINT_BINARY_BUILDER_IMAGE} -c 'tar -pzcf - \
    /usr/local/share/.cache/yarn/v*/ \
    /usr/local/share/.config/yarn/global' > asset-theia-endpoint-runtime-binary-yarn-"$(uname -m)".tar.gz

  ${DOCKERRUN} --rm --entrypoint sh ${TMP_THEIA_ENDPOINT_BINARY_BUILDER_IMAGE} -c \
    'cd /tmp && tar -pzcf - nexe-cache' > asset-theia-endpoint-runtime-pre-assembly-nexe-cache-"$(uname -m)".tar.gz
  ${DOCKERRUN} --rm --entrypoint sh ${TMP_THEIA_ENDPOINT_BINARY_BUILDER_IMAGE} -c \
    'cd /tmp && tar -pzcf - nexe' > asset-theia-endpoint-runtime-pre-assembly-nexe-"$(uname -m)".tar.gz

  # node-src
  download_url="https://nodejs.org/download/release/v${nodeVersion}/node-v${nodeVersion}.tar.gz"
  echo -n "Local node version: "; node --version
  echo "Requested node version: v${nodeVersion}"
  echo "URL to curl: ${download_url}"
  curl -sSL "${download_url}" -o asset-node-src.tar.gz
  # ${DOCKERRUN} --rm --entrypoint sh ${TMP_THEIA_ENDPOINT_BINARY_BUILDER_IMAGE} -c 'nodeVersion=$(node --version); \
  # download_url="https://nodejs.org/download/release/${nodeVersion}/node-${nodeVersion}.tar.gz" && curl ${download_url}' > asset-node-src.tar.gz

  popd >/dev/null || exit 1
  listAssets "${BREW_DOCKERFILE_ROOT_DIR}"/theia-endpoint-runtime-binary
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
  ${DOCKERRUN} rmi -f $TMP_THEIA_DEV_BUILDER_IMAGE $TMP_THEIA_BUILDER_IMAGE $TMP_THEIA_RUNTIME_IMAGE $TMP_THEIA_ENDPOINT_BINARY_BUILDER_IMAGE || true
fi

set +x
echo; echo "Asset tarballs generated. See the following folder(s) for content to upload to pkgs.devel.redhat.com:"
for step in $STEPS; do
  output_dir=${step//_/-};output_dir=${output_dir/collect-assets-crw-/}
  echo " - ${BREW_DOCKERFILE_ROOT_DIR}/${output_dir}"
done
echo
