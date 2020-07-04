#!/usr/bin/env bash

: ${CCI_SRC:=/c/cci}
: ${LKP_SRC:=/c/lkp-tests}

$CCI_SRC/providers/my-qemu.sh
