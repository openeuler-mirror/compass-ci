#!/bin/bash

[[ $tbox_group ]] ||
tbox_group=vm-hi1620-2p8g
export hostname=$tbox_group--$USER-$$

$CCI_SRC/providers/qemu.sh
