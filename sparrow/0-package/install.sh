#!/bin/bash

source /etc/os-release

. $(dirname ${BASH_SOURCE[0]})/os/${ID}

. $(dirname ${BASH_SOURCE[0]})/common.sh
