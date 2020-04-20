#!/bin/bash

cmd=(
	docker run
	-it
#	--name initrd-http
	-p 8800:80
	-v /srv/initrd:/usr/share/nginx/html/initrd:ro
	-d
	initrd-http
)

"${cmd[@]}"
