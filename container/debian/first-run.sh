#!/bin/bash

cmd=(
	docker run
	-it
	-e SSH_KEYS="$(</etc/ssh/team.pub)"
	-e COMMITTERS="$(awk -F: '/^committer:/ {print $4}' /etc/group)"
	-v debian-home:/home
	-v debian-root:/root
	-v /etc/skel:/mnt/skel
	-v $CCI_SRC/container/setup.sh:/usr/local/sbin/setup.sh
	debian:testbed
	/usr/local/sbin/setup.sh
)

"${cmd[@]}"
