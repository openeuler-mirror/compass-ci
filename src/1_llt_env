#!/usr/bin/env bash

SCHED_DEBUG_DIR=/c/cci/scheduler
DIR=$(dirname $(realpath $0))

if [ ! -d test ]; then
  mkdir test
fi

cmd=(
  docker run
  --rm
  -e LKP_SRC=/c/lkp-tests
  -e CRYSTAL_PATH="/usr/share/crystal/app/lib:/usr/lib/crystal/shards:/usr/lib/crystal/core:$SCHED_DEBUG_DIR"
  -it
  -u $UID
  -v $DIR:$SCHED_DEBUG_DIR
  -v $DIR/test:/result
  -v $LKP_SRC:/c/lkp-tests
  -w $SCHED_DEBUG_DIR
  alpine:scheduler-dev
  sh
)

"${cmd[@]}"

