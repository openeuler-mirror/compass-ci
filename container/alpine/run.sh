#!/bin/bash

cmd=(
	docker run
	-it
	-v vhome:/home
	-v vroot:/root
	-v /c:/c
	-v /os:/os
	-p 2200:2200
	--hostname alpine
	--name alpine
	--security-opt seccomp=unconfined
	-d
	alpine:testbed
	/usr/sbin/sshd -D -p 2200
)

"${cmd[@]}"
