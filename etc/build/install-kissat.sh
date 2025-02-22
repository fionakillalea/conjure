#!/bin/bash

set -o errexit
set -o nounset

export BIN_DIR=${BIN_DIR:-${HOME}/.local/bin}

rm -rf tmp-install-kissat
mkdir tmp-install-kissat
pushd tmp-install-kissat
git clone https://github.com/arminbiere/kissat.git
cd kissat
# latest on Github as of 24 September 2020, around when they won the SAT competition
git checkout rel-1.1.1
./configure
make kissat
cp build/kissat ${BIN_DIR}/kissat
echo "kissat executable is at ${BIN_DIR}/kissat"
ls -l ${BIN_DIR}/kissat
popd
rm -rf tmp-install-kissat

