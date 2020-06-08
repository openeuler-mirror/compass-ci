#!/usr/bin/env bash

SCHED_DEBUG_DIR=/c/cci/scheduler
DIR=$(dirname $(realpath $0))

lib_folder="$DIR/lib"
if [ ! -d "$lib_folder" ] && [ ! -f "$lib_folder" ]; then
  if [ ! -L "$lib_folder" ]; then
    ln -s /usr/share/crystal/app/lib $lib_folder
  fi
fi

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

