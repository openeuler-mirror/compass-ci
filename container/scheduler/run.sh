#!/bin/bash

LKP_SRC=/c/lkp-tests

cmd=(
	docker run
	--name s001-alpine
	-d
	-u 1090:1090
	-p 3000:3000
	-e LKP_SRC=$LKP_SRC
	-v $LKP_SRC:$LKP_SRC
	-v /srv/scheduler/alpine:/srv/scheduler
	-w /usr/share/scheduler
	sch-ruby-a:v0.00e
        ./scheduler
)

"${cmd[@]}"

