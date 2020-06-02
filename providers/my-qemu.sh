#!/bin/bash

[[ $tbox_group ]] ||
tbox_group=vm-pxe-hi1620-1p1g
export hostname=$tbox_group-$USER-$$

cp $LKP_SRC/hosts/$tbox_group \
   $LKP_SRC/hosts/$tbox_group-$USER

./qemu.sh
