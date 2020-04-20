#!/bin/bash

cmd=(
	docker run
	-it
#	--name os-http
	-p 8000:80
	-v /srv/os:/usr/share/nginx/html/os:ro
	-d
	os-http
)

"${cmd[@]}"
