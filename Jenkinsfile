#!/usr/bin/env groovy

// PARAMETERS for this pipeline:
// branchToBuildCRW = codeready-workspaces branch to build: */2.0.x or */master
// THEIA_BRANCH = theia branch/tag to build: master, 8814c20, v0.11.0
// CHE_THEIA_BRANCH = che-theia branch to build: master, 7.3.1, 7.3.0
// node == slave label, eg., rhel7-devstudio-releng-16gb-ram||rhel7-16gb-ram||rhel7-devstudio-releng||rhel7 or rhel7-32gb||rhel7-16gb||rhel7-8gb
// GITHUB_TOKEN = (github token)
// USE_PUBLIC_NEXUS = true or false (if true, don't use https://repository.engineering.redhat.com/nexus/repository/registry.npmjs.org)

def installNPM(){
	def nodeHome = tool 'nodejs-10.15.3'
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

npm install --global yarn
npm config get; yarn config get list
npm --version; yarn --version
'''
	}
	else
	{
		sh '''#!/bin/bash -xe
rm -f ${HOME}/.npmrc ${HOME}/.yarnrc
npm install --global yarn
npm --version; yarn --version
'''
	}
}

timeout(120) {
	node("${node}"){ stage "Build Theia"
		cleanWs()
		// for private repo, use checkout(credentialsId: 'devstudio-release')
		checkout([$class: 'GitSCM', 
			branches: [[name: "${branchToBuildCRW}"]], 
			doGenerateSubmoduleConfigurations: false, 
			poll: true,
			extensions: [[$class: 'RelativeTargetDirectory', relativeTargetDir: "crw-theia"]], 
			submoduleCfg: [], 
			userRemoteConfigs: [[url: "https://github.com/redhat-developer/codeready-workspaces-theia.git"]]])
		installNPM()

		// CRW-360 use RH NPM mirror
		// if ("${USE_PUBLIC_NEXUS}".equals("false")) {
		// 	sh '''#!/bin/bash -xe 
		// 	for d in $(find . -name yarn.lock -o -name package.json); do 
		// 		sed -i $d 's|https://registry.yarnpkg.com/|https://repository.engineering.redhat.com/nexus/repository/registry.npmjs.org/|g'
		// 	'''
		// }

		// check available disk space -- might need to do some cleanup if this slave is getting full
		sh '''#!/bin/bash -xe 
		df -h  ${WORKSPACE} /tmp / /home/hudson/static_build_env /qa/tools
		'''

		// increase verbosity of yarn calls to we can log what's being downloaded from 3rd parties - doesn't work at this stage; must move into build.sh
		sh '''#!/bin/bash -xe 
		for d in $(find . -name package.json); do sed -i $d -e 's#yarn #yarn --verbose #g'; done
		'''

		// TODO pass che-theia and theia tags/branches to this script
		def BUILD_PARAMS="--ctb ${THEIA_BRANCH} --tb ${CHE_THEIA_BRANCH} --all --squash --no-cache --rmi:all"
		sh '''#!/bin/bash -xe
		export GITHUB_TOKEN="''' + GITHUB_TOKEN + '''"
		mkdir -p ${WORKSPACE}/logs/
		pushd ${WORKSPACE}/crw-theia >/dev/null
			./build.sh ''' + BUILD_PARAMS + ''' | tee ${WORKSPACE}/logs/crw-theia_buildlog.txt
		popd >/dev/null
		'''

		// check available disk space -- might need to do some cleanup if this slave is getting full
		sh '''#!/bin/bash -xe 
		df -h  ${WORKSPACE} /tmp / /home/hudson/static_build_env /qa/tools
		'''
		// TODO verify this works & is archived correctly
		archiveArtifacts fingerprint: true, artifacts: "\
			crw-theia/dockerfiles/**/*, \
			crw-theia/dockerfiles/**/**/*, \
			crw-theia/dockerfiles/**/**/**/*, \
			crw-theia/dockerfiles/**/**/**/**/*, \
			crw-theia/dockerfiles/**/**/**/**/**/*, \
			crw-theia/dockerfiles/**/**/**/**/**/**/*, \
			logs/*"

		// TODO start collecting shas with "git rev-parse --short=4 HEAD"
		def descriptString="Build #${BUILD_NUMBER} (${BUILD_TIMESTAMP}) <br/> :: crw-theia @ ${branchToBuildCRW}, che-theia @ ${CHE_THEIA_BRANCH}, theia @ ${THEIA_BRANCH}"
		echo "${descriptString}"
		currentBuild.description="${descriptString}"

	    writeFile(file: 'project.rules', text:
'''
# warnings/errors to ignore
ok /Couldn't create directory: Failure/

# section starts: these are used to group errors and warnings found after the line; also creates a quick access link.
start /====== handle_.+/

# warnings
warning /.+\[WARNING\].+/
warning /[Ww]arning/
warning /WARNING/
warning /Connection refused/

# errors
error / \[ERROR\] /
error /exec returned: .+/
error /non-zero code/
error /ripgrep: Command failed/
error /The following error occurred/

# match line starting with 'error ', case-insensitive
error /(?i)^error /
''')
    step([$class: 'LogParserPublisher',
        failBuildOnError: true,
        projectRulePath: 'project.rules',
        useProjectRule: true])
	}
}

// TODO enable downstream image builds
// timeout(120) {
// 	node("${node}"){ stage "Run get-sources-rhpkg-container-build"
// 		def QUAY_REPO_PATHs=(env.ghprbPullId && env.ghprbPullId?.trim()?"":("${SCRATCH}"=="true"?"":"server-rhel8"))

// 		def matcher = ( "${JOB_NAME}" =~ /.*_(stable-branch|master).*/ )
// 		def JOB_BRANCH= (matcher.matches() ? matcher[0][1] : "stable-branch")

// 		echo "[INFO] Trigger get-sources-rhpkg-container-build " + (env.ghprbPullId && env.ghprbPullId?.trim()?"for PR-${ghprbPullId} ":"") + \
// 		"with SCRATCH = ${SCRATCH}, QUAY_REPO_PATHs = ${QUAY_REPO_PATHs}, JOB_BRANCH = ${JOB_BRANCH}"

// 		// trigger OSBS build
// 		build(
// 		  job: 'get-sources-rhpkg-container-build',
// 		  wait: false,
// 		  propagate: false,
// 		  parameters: [
// 			[
// 			  $class: 'StringParameterValue',
// 			  name: 'GIT_PATH',
// 			  value: "containers/codeready-workspaces",
// 			],
// 			[
// 			  $class: 'StringParameterValue',
// 			  name: 'GIT_BRANCH',
// 			  value: "crw-2.0-rhel-8",
// 			],
// 			[
// 			  $class: 'StringParameterValue',
// 			  name: 'QUAY_REPO_PATHs',
// 			  value: "${QUAY_REPO_PATHs}",
// 			],
// 			[
// 			  $class: 'StringParameterValue',
// 			  name: 'SCRATCH',
// 			  value: "${SCRATCH}",
// 			],
// 			[
// 			  $class: 'StringParameterValue',
// 			  name: 'JOB_BRANCH',
// 			  value: "${JOB_BRANCH}",
// 			]
// 		  ]
// 		)
// 	}
// }
