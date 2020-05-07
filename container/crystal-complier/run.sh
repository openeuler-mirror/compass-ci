#!/bin/bash

cmd=(
	docker run
	-u $UID 
	--rm
	-it
	-v $LKP_SRC:$LKP_SRC
	-w $PWD 	 
	alpine:crystal-complier
	crystal build --static "$@"
)

"${cmd[@]}"
