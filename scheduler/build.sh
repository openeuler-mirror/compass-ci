#!/usr/bin/env bash

SCHED_DEBUG_DIR=/c/cci/scheduler
DIR=$(dirname $(realpath $0))

cmd=(
  docker run
  --rm
  -e CRYSTAL_PATH="/usr/share/crystal/app/lib:/usr/lib/crystal/shards:/usr/lib/crystal/core:$SCHED_DEBUG_DIR"
  -it
  -u $UID
  -v $DIR:$SCHED_DEBUG_DIR
  -w $SCHED_DEBUG_DIR
  alpine:scheduler-dev
  sh -c "crystal build scheduler.cr -o m_scheduler"
)

"${cmd[@]}"
