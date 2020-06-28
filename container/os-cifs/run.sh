#!/bin/bash


cmd=(
 	docker run -dt 
	-p 445:445
	-v $PWD/smb.conf:/etc/samba/smb.conf
	-v /srv/os:/srv/os:ro
	--name samba
	--restart=always
	alpine/samba
)

"${cmd[@]}"
