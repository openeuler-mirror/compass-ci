#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

if [ -f /etc/ssh/team.pub ]; then
        ssh_keys="$(</etc/ssh/team.pub)"
else
        ssh_keys=""
fi

cmd=(
	docker run
	--cidfile=/tmp/cid-$$
	-e SSH_KEYS="${ssh_keys}"
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
