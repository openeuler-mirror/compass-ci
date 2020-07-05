#!/bin/bash

cmd=(
	docker run
	-it
	--cidfile=/tmp/cid-$$
	-e SSH_KEYS="$(</etc/ssh/team.pub)"
	-e COMMITTERS="$(awk -F: '/^committer:/ {print $4}' /etc/group)"
	-e TEAM="$(      awk -F: '/^team:/      {print $4}' /etc/group)"
	-v alpine-home:/home
	-v alpine-root:/root
	-v /etc/skel:/mnt/skel
	-v /etc/passwd:/opt/passwd
	-v $CCI_SRC/container/setup.sh:/usr/local/sbin/setup.sh
	alpine:testbed
	/usr/local/sbin/setup.sh
)

"${cmd[@]}"

docker commit $(</tmp/cid-$$) alpine:testbed
