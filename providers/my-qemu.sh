#!/bin/bash

[[ $tbox_group ]] ||
tbox_group=vm-hi1620-2p8g
export hostname=$tbox_group-$USER-$$

cp $LKP_SRC/hosts/$tbox_group \
   $LKP_SRC/hosts/$tbox_group-$USER

./qemu.sh
