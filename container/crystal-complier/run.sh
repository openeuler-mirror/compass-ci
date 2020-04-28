#!/bin/bash

cmd=(
	docker run
	-u $UID 
	--rm
	-it
	-v $PWD:/mnt
	-w /mnt
	alpine:crystal-complier
	crystal build --static "$@"
)

"${cmd[@]}"
