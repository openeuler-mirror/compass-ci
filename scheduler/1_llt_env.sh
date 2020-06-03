#!/usr/bin/env bash


DIR=$(dirname $(realpath $0))
cDIR=${DIR##*/}

cmd=(
	docker run
	--rm
	-e LKP_SRC=/c/lkp-tests
	-it
	-u $UID
	-v $DIR:/usr/share/code
	-v $LKP_SRC:/c/lkp-tests
	-w /usr/share/code
	alpine:scheduler-dev
	sh
)

"${cmd[@]}"

