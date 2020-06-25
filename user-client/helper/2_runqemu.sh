#!/usr/bin/bash

: ${CCI_SRC:=/c/cci}
: ${LKP_SRC:=/c/lkp-tests}

cd /c/cci/providers

./qemu.sh
