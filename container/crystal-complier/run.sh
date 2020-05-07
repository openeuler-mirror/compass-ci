#!/bin/bash
pj_dir=`git rev-parse --show-toplevel`
echo $pj_dir
cmd=(
	docker run
	-u $UID 
	--rm
	-it
	-v $pj_dir:$pj_dir
	-w $PWD 	 
	alpine:crystal-complier
	crystal build --static "$@"
)

"${cmd[@]}"
