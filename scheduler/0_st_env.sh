#!/usr/bin/env bash

docker stop s001-alpine

SCHED_DEBUG_DIR=/c/cci/scheduler
DIR=$(dirname $(realpath $0))

[[ $LKP_SRC ]] || LKP_SRC=/c/lkp-tests

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
	-p 3000:3000
	-u $UID
	-v $DIR:$SCHED_DEBUG_DIR
	-v $LKP_SRC:/c/lkp-tests
	-w $SCHED_DEBUG_DIR
	alpine:scheduler-dev
	sh
)

"${cmd[@]}"


docker restart s001-alpine
