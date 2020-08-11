#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+

cmd=(
	docker run
	--cidfile=/tmp/cid-$$
	-e SSH_KEYS="$(</etc/ssh/team.pub)"
	-e COMMITTERS="$(awk -F: '/^committer:/ {print $4}' /etc/group)"
	-e TEAM="$(      awk -F: '/^team:/      {print $4}' /etc/group)"
	-v $OS-home:/home
	-v $OS-root:/root
	-v /etc/skel:/mnt/skel
	-v /etc/passwd:/opt/passwd
	-v $CCI_SRC/container/setup.sh:/usr/local/sbin/setup.sh
	$OS:testbed
	/usr/local/sbin/setup.sh
)

"${cmd[@]}"

docker commit $(</tmp/cid-$$) $OS:testbed
