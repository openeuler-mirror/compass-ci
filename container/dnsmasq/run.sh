#!/bin/bash

cmd=(
	docker run
	--cap-add NET_ADMIN
	--net=host
	--publish 67:67/udp
	--publish 69:69/udp
	-v $PWD/dnsmasq.d:/etc/dnsmasq.d
	-v /tftpboot:/tftpboot:ro
	-it
	--detach
	dnsmasq:alpine
	dnsmasq -k
)

"${cmd[@]}"
