#!/usr/bin/env bash

SCHED_DEBUG_DIR=/c/cci/scheduler
DIR=$(dirname $(realpath $0))

cmd=(
	docker run
	--rm
	-e LKP_SRC=/c/lkp-tests
	-it
	-u $UID
	-v $DIR:$SCHED_DEBUG_DIR
	-v $LKP_SRC:/c/lkp-tests
	-w $SCHED_DEBUG_DIR
	alpine:scheduler-dev
	sh
)

"${cmd[@]}"

