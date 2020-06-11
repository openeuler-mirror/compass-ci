#!/bin/bash
. ../lab.sh

cmd=(
	docker run
	-it
#	--name os-http
	-p ${OS_HTTP_PORT:-8000}:80
	-v /srv/os:/usr/share/nginx/html/os:ro
	-d
	os-http
)

"${cmd[@]}"
