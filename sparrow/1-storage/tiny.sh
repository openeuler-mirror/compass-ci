#!/bin/bash

dirs=(
	/srv/es
	/srv/git
	/srv/initrd
	/srv/os
	/srv/redis
	/srv/result
	/srv/scheduler
)

mkdir -p "${dirs[@]}"
