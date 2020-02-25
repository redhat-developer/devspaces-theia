# to build CRW Theia

# required build-args
# GITHUB_TOKEN=YOUR_TOKEN_HERE

# optional build-args
# CHE_THEIA_BRANCH=7.9.0
# THEIA_BRANCH=master
# NODE_VERSION=10.16.3
# YARN_VERSION=1.17.3

docker build . -t crw-theia-build --build-arg GITHUB_TOKEN=$1
