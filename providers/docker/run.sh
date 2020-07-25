#!/bin/bash
: ${docker_image:="centos:7"}
: ${load_path:="${HOME}/jobs"}

DIR=$(dirname $(realpath $0))
cmd=(
	docker run 
	-it
	--rm
	-v ${LKP_SRC}:/lkp/lkp/src:ro
	-v ${load_path}/lkp/scheduled:/lkp/scheduled:ro
	-v ${DIR}/bin:/root/bin:ro
	${docker_image} 
	/root/bin/entrypoint.sh
)

"${cmd[@]}" 
