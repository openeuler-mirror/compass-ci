#!/bin/bash

LKP_SRC=/c/lkp-tests
DIR=$(dirname $(realpath $0))

cmd=(
	docker run
	--rm
	-it
	-e LKP_SRC=$LKP_SRC
	-v $LKP_SRC:$LKP_SRC
	-v $DIR/bin:/root/bin
	-v /srv/initrd/lkp/latest:/osimage/user/lkp
	alpine:lkp
	/root/bin/pack-lkp.sh
)

"${cmd[@]}"
