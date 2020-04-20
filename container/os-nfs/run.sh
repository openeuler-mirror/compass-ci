#!/bin/bash

cmd=(
	docker run
#	-it
#	--name os
	-e NFS_DISABLE_VERSION_3=1
	-v /srv/os:/exports/os:ro
	-v /srv/result:/exports/result
	--cap-add SYS_ADMIN
#	--privileged
	--net=host # w/o it, docker-proxy only listens on tcp6..
#	-p 2049:2049
	-d # comment out to see debug output
	os-nfs
)

"${cmd[@]}"
