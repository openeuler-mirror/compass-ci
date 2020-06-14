#!/bin/bash

[[ $CCI_LAB ]] || CCI_LAB=sparrow
[[ $LKP_SRC ]] || LKP_SRC=/c/lkp-tests

. $LKP_SRC/lib/yaml.sh
create_yaml_variables "$LKP_SRC/labs/${CCI_LAB}.yaml"

DIR=$(dirname $(realpath $0))
cmd=(
	docker run
	--rm
	-it
	-e LKP_SRC=$LKP_SRC
	-v $LKP_SRC:$LKP_SRC
	-v $DIR/bin:/root/bin
	-v /srv/initrd/lkp/${lkp_initrd_user:-latest}:/osimage/user/lkp
	alpine:lkp
	/root/bin/pack-lkp.sh
)

"${cmd[@]}"
