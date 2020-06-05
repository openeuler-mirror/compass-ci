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
	-v /srv/scheduler/alpine:/srv/scheduler
	-v /etc/localtime:/etc/localtime:ro
	-w /usr/share/scheduler
	sch-ruby-a:v0.00d
        ./scheduler
)

"${cmd[@]}"

