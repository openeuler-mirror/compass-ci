#!/bin/bash

cmd=(
	docker run
	-it
	-v vhome:/home
	-v vroot:/root
	-v /c:/c
	-v /os:/srv/os
	-p 2201:2201
	-p 1301:1301
	--hostname debian
	--name debian
	--security-opt seccomp=unconfined
	-d
	debian:testbed
	/usr/sbin/sshd -D -p 2201
)

"${cmd[@]}"
