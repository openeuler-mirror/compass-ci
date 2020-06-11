#!/bin/sh -e

cd /c

git clone https://github.com/sds/overcommit.git || exit

cd overcommit

oc_build_out=$(gem build overcommit.gemspec | grep "overcommit-.*\.gem")

gem install "$oc_build_out"
