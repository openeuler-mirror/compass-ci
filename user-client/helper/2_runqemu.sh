#!/usr/bin/bash

: ${CCI_SRC:=/c/cci}
: ${LKP_SRC:=/c/lkp-tests}

cd /tftpboot/
rm ./boot.ipxe
ln -s ./boot.ipxe-chief ./boot.ipxe

cd /c/cci/providers

./qemu.sh
