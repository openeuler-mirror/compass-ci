#!/bin/bash

cmd=(
	docker run
	-it
	-v alpine-home:/home
	-v alpine-root:/root
	-v /etc/skel:/mnt/skel
	-v $CCI_SRC/container/setup.sh:/usr/local/sbin/setup.sh
	-e SSH_KEYS="$(</etc/ssh/team.pub)"
	alpine:testbed
	bash
	/usr/local/sbin/setup.sh
)

"${cmd[@]}"
