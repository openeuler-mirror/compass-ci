#!/bin/bash
. ../lab.sh

docker rm -f s001-alpine-${SCHED_PORT:-3000}

cmd=(
	docker run
	--name s001-alpine-${SCHED_PORT:-3000}
	-d
	-u 1090:1090
	-p ${SCHED_PORT:-3000}:${SCHED_PORT:-3000}
	-e LKP_SRC=/c/lkp-tests
	-e SCHED_HOST=${SCHED_HOST:-172.17.0.1}
	-e SCHED_PORT=${SCHED_PORT:-3000}
	-e REDIS_HOST=${REDIS_HOST:-172.17.0.1}
	-e REDIS_PORT=${REDIS_PORT:-6379}
	-e ES_HOST=${ES_HOST:-172.17.0.1}
	-e ES_PORT=${ES_PORT:-9200}
	-e INITRD_HTTP_HOST=${INITRD_HTTP_HOST:-172.168.131.113}
	-e INITRD_HTTP_PORT=${INITRD_HTTP_PORT:-8800}
	-e OS_HTTP_HOST=${OS_HTTP_HOST:-172.168.131.113}
	-e OS_HTTP_PORT=${OS_HTTP_PORT:-8000}
	-v $LKP_SRC:/c/lkp-tests
	-v /srv/cci/scheduler/alpine:/srv/cci/scheduler
	-v /etc/localtime:/etc/localtime:ro
	-v /srv/result:/result
	-v /srv/initrd:/srv/initrd
	sch-ruby-a:v0.00d-${SCHED_PORT:-300}
	sh -c "umask 002 && ./scheduler"
)

"${cmd[@]}"

