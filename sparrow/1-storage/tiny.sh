#!/bin/bash

dirs=(
	/srv/es
	/srv/git
	/srv/initrd
	/srv/initrd/pkg
	/srv/initrd/deps
	/srv/os
	/srv/redis
	/srv/result
	/srv/cci/scheduler
	/tftpboot
)

mkdir -p "${dirs[@]}"
chgrp lkp /srv/result
chmod 775 /srv/result
