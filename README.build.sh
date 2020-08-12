# to build CRW Theia

# required build-args
# GITHUB_TOKEN=YOUR_TOKEN_HERE

# optional build-args - see Dockerfile
# ARG CHE_THEIA_BRANCH=7.17.x
# ARG THEIA_BRANCH=master
# ARG NODE_VERSION=10.19.0
# ARG YARN_VERSION=1.17.3

docker build . -t crw-theia-build --build-arg GITHUB_TOKEN=$1
