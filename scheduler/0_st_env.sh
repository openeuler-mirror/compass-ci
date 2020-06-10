#!/usr/bin/env bash

docker stop s001-alpine

SCHED_DEBUG_DIR=/c/cci/scheduler
DIR=$(dirname $(realpath $0))

[[ $LKP_SRC ]] || LKP_SRC=/c/lkp-tests

if [ ! -d test ]; then
  mkdir test
fi

cmd=(
  docker run
  --rm
  -e LKP_SRC=/c/lkp-tests
  -e CRYSTAL_PATH="/usr/share/crystal/app/lib:/usr/lib/crystal/shards:/usr/lib/crystal/core:$SCHED_DEBUG_DIR"
  -it
  -p 3000:3000
  -u $UID
  -v $DIR:$SCHED_DEBUG_DIR
  -v $LKP_SRC:/c/lkp-tests
  -v $DIR/test:/result
  -w $SCHED_DEBUG_DIR
  alpine:scheduler-dev
  sh
)

"${cmd[@]}"


docker restart s001-alpine
