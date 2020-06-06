#!/usr/bin/env bash

docker stop s001-alpine

SCHED_DEBUG_DIR=/c/cci/scheduler
DIR=$(dirname $(realpath $0))

cmd=(
	docker run
	--rm
	-e LKP_SRC=/c/lkp-tests
	-it
	-p 3000:3000
	-u $UID
	-v $DIR:$SCHED_DEBUG_DIR
	-v /c/lkp-tests:/c/lkp-tests
	-w $SCHED_DEBUG_DIR
	alpine:scheduler-dev
	sh
)

"${cmd[@]}"


docker restart s001-alpine
