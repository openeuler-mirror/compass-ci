#!/bin/bash

SCHED_DEBUG_DIR=/c/cci/scheduler
DIR=$(dirname $(realpath $0))
filename=${DIR##*/}

lib_ln="$DIR/lib"
if [ ! -d $lib_ln ] && [ ! -f $lib_ln ]; then
  if [ ! -L $lib_ln ]; then
    ln -s /usr/share/crystal/app/lib $lib_ln
  fi
fi

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

