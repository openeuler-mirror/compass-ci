#!/bin/bash
pj_dir=`git rev-parse --show-toplevel 2>/dev/null`
if [ $pj_dir ];then
    v_dir=$pj_dir
else
    v_dir=$PWD
fi
cmd=(
	docker run
	-u $UID 
	--rm
	-it
	-v $v_dir:$v_dir
	-w $PWD 	 
	alpine:crystal-complier
	crystal build --static "$@"
)

"${cmd[@]}"
