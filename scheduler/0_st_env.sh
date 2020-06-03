#!/usr/bin/env bash

docker stop s001-alpine

DIR=$(dirname $(realpath $0))
cDIR=${DIR##*/}

cmd=(
	docker run
	--rm
	-e LKP_SRC=/c/lkp-tests
	-it
	-p 3000:3000
	-u $UID
	-v $DIR:/usr/share/code
	-v /c/lkp-tests:/c/lkp-tests
	-w /usr/share/code
	alpine:scheduler-dev
	sh
)

"${cmd[@]}"


docker restart s001-alpine
