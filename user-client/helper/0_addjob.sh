#!/usr/bin/bash

DIR=$(dirname $(realpath $0))
ruby $DIR/../src/lkp.rb queue $1
