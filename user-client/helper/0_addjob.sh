#!/usr/bin/env bash
# SPDX-License-Identifier: MulanPSL-2.0+

DIR=$(dirname $(realpath $0))
ruby $DIR/../src/lkp.rb queue $1
