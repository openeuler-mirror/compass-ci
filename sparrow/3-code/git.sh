#!/bin/bash

# download git trees

mkdir -p /c
cd /c

# git clone https://gitee.com/openeuler/crystal-ci.git
# modify and manual run for now:
git clone git://$GIT_SERVER/crystal-ci/crystal-ci.git
ln -s crystal-ci cci

git clone git://$GIT_SERVER/lkp-tests/lkp-tests.git
