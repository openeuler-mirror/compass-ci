#!/bin/bash

SCHED_DEBUG_DIR=/c/cci/scheduler
DIR=$(dirname $(realpath $0))
filename=${DIR##*/}

cmd=(
	docker run
	--rm
	-it
	-u $UID
	-v $DIR:$SCHED_DEBUG_DIR
	-w $SCHED_DEBUG_DIR
	alpine:scheduler-dev
	sh -c "crystal build src/$filename.cr"
)

"${cmd[@]}"

