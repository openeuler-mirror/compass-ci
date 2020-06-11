#!/bin/bash

docker stop s001-alpine
docker rm s001-alpine

[[ $LKP_SRC ]] || LKP_SRC=/c/lkp-tests

cmd=(
	docker run
	--name s001-alpine
	-d
	-u 1090:1090
	-p 3000:3000
	-e LKP_SRC=/c/lkp-tests
	-v $LKP_SRC:/c/lkp-tests
	-v /srv/cci/scheduler/alpine:/srv/cci/scheduler
	-v /etc/localtime:/etc/localtime:ro
	-v /srv/result:/result
	sch-ruby-a:v0.00d
	sh -c "umask 002 && ./scheduler"
)

"${cmd[@]}"

