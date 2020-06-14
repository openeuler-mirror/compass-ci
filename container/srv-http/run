#!/bin/bash

cmd=(
	docker run
	-it
	-p 11300:80
	-v /srv:/usr/share/nginx/html/srv:ro
	-d
	srv-http
)

"${cmd[@]}"
