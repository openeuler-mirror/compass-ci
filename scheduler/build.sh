#!/bin/bash

SCHED_DEBUG_DIR=/c/cci/scheduler
DIR=$(dirname $(realpath $0))
cDIR=${DIR##*/}

cmd=(
	docker run
	--rm
	-it
	-u $UID
	-v $DIR:$SCHED_DEBUG_DIR
	-w $SCHED_DEBUG_DIR
	alpine:scheduler-dev
	sh -c "crystal build src/$cDIR.cr"
)

"${cmd[@]}"

