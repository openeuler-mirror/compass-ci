#!/bin/bash

[[ -e /tftpboot/boot.ipxe ]] || {
    cp tftpboot/boot.ipxe /tftpboot/boot.ipxe
}

docker build -t dnsmasq:alpine .
