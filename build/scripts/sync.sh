#!/bin/bash
#
# Copyright (c) 2021 Red Hat, Inc.
# This program and the accompanying materials are made
# available under the terms of the Eclipse Public License 2.0
# which is available at https://www.eclipse.org/legal/epl-2.0/
#
# SPDX-License-Identifier: EPL-2.0
#
# Contributors:
#   Red Hat, Inc. - initial API and implementation
#
# copy generated midstream crw-theia project files to crw-images project using sed
# see also ../../build.sh, which will generate content in this repo. 
# Use build.sh --commit to push changes into this repo before syncing to lower midsteam

set -e

COMMIT_CHANGES=0 # by default, don't commit anything that changed; optionally, use GITHUB_TOKEN to push changes to the current branch

usage () {
    echo "
Usage:   $0 -s /path/to/crw-theia -t /path/to/generated
Example: $0 -s ${HOME}/projects/crw-theia -t /tmp/crw-images/"
    exit
}

if [[ $# -lt 4 ]]; then usage; fi

while [[ "$#" -gt 0 ]]; do
  case $1 in
    # paths to use for input and ouput
    '-s') SOURCEDIR="$2"; SOURCEDIR="${SOURCEDIR%/}"; shift 2;;
    '-t') TARGETDIR="$2"; TARGETDIR="${TARGETDIR%/}"; shift 2;;
    '--commit') COMMIT_CHANGES=1; shift 1;;
    '--help'|'-h') usage;;
  esac
done

if [[ ! -d "${SOURCEDIR}" ]]; then usage; fi
if [[ ! -d "${TARGETDIR}" ]]; then usage; fi
if [[ "${CSV_VERSION}" == "2.y.0" ]]; then usage; fi

# global / generic changes
echo ".github/
.git/
.gitattributes
build/scripts/sync.sh
/container.yaml
/content_sets.*
/cvp.yml
get-sources-jenkins.sh
tests/basic-test.yaml
sources
rhel.Dockerfile
bootstrap.Dockerfile
asset-unpacked-generator
" > /tmp/rsync-excludes

sync_crwtheia_to_crwimages() {
  echo "Rsync ${1} to ${2}"
  rsync -azrlt --checksum --exclude-from /tmp/rsync-excludes ${1}/ ${2}/ # --delete 
  # ensure shell scripts are executable
  find "${1}/" -name "*.sh" -exec chmod +x {} \;
}

sync_crwtheia_to_crwimages "${SOURCEDIR}/dockerfiles/theia-dev" "${TARGETDIR}/codeready-workspaces-theia-dev"
sync_crwtheia_to_crwimages "${SOURCEDIR}/dockerfiles/theia" "${TARGETDIR}/codeready-workspaces-theia"
sync_crwtheia_to_crwimages "${SOURCEDIR}/dockerfiles/theia-endpoint-runtime-binary" "${TARGETDIR}/codeready-workspaces-theia-endpoint"

rm -f /tmp/rsync-excludes

pushd "${TARGETDIR}" >/dev/null || exit 1
  # TODO verify this works
  # undelete any files that might not exist in crw-theia (because they're created from container builds? multiarch?)
  # deletedFiles="$(git status -s | sed -e "s# D ##")"
  # if [[ $deletedFiles ]]; then 
  #   echo "Undelete these files:"
  #   for df in $deletedFiles; do
  #     echo "* $df"; git restore $df
  #   done
  # fi

  # commit changed files to this repo
  if [[ ${COMMIT_CHANGES} -eq 1 ]]; then
    git update-index --refresh || true  # ignore timestamp updates
    if [[ $(git diff-index HEAD --) ]]; then # file changed
      git add codeready-workspaces-theia*/
      echo "[INFO] Commit generated dockerfiles, lock files, and asset lists"
      git commit -s -m "chore: sync crw-theia to crw-images/crw-theia*/"
      git pull || true
      git push || true
    fi
  fi

popd >/dev/null || exit

