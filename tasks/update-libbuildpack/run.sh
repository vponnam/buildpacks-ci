#!/bin/bash -l

set -o errexit
set -o nounset
set -o pipefail

set -x

export GOPATH=$PWD/buildpack
export GOBIN=/usr/local/bin

pushd buildpack/src/compile
  go get github.com/FiloSottile/gvt
  go get github.com/golang/mock/gomock
  go get github.com/golang/mock/mockgen
  go get github.com/onsi/ginkgo/ginkgo
  go get github.com/onsi/gomega

  gvt update github.com/cloudfoundry/libbuildpack
  go generate
  ginkgo -r
popd

pushd buildpack
  git add src/compile

  set +e
    git diff --cached --exit-code
    no_changes=$?
  set -e

  if [ $no_changes -ne 0 ]
  then
    git commit -m "Update libbuildpack"
  else
    echo "libbuildpack is up to date"
  fi
popd

rsync -a buildpack/ buildpack-artifacts