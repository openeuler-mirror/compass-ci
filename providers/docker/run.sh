#!/bin/bash
: ${docker_image:="centos:7"}
: ${load_path:="${HOME}/jobs"}

DIR=$(dirname $(realpath $0))
cmd=(
	docker run 
	-it
	--rm
	--mount type=tmpfs,destination=/tmp
	-v ${load_path}/lkp:/lkp
	-v ${DIR}/bin:/root/bin:ro
	${docker_image} 
	/root/bin/entrypoint.sh
)

"${cmd[@]}" 
