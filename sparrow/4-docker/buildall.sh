#!/bin/bash -e

[[ $CCI_SRC ]] || export CCI_SRC=$(dirname $(dirname $(dirname $(realpath $0))))
CONTAINER_PATH="$CCI_SRC/container"

for dir in $CONTAINER_PATH/*
do
	[ "${dir##*/}" == 'scheduler' ] && {
		echo "${dir##*/} not ready to build&run, skip!"
		continue
	}
	cd "$dir"
	./build.sh
	[ "${dir##*/}" == 'debian' ] || \
	[ "${dir##*/}" == 'lkp-initrd' ] || \
	[ "${dir##*/}" == 'dracut-initrd' ] || \
	[ "${dir##*/}" == 'crystal-base' ] || \
	[ "${dir##*/}" == 'scheduler-dev' ] && {
		echo "${dir##*/} just build, skip!"
		continue
	}
	[ "${dir##*/}" == 'es' ] && {
		echo "${dir##*/} not ready to run, skip!"
		continue
	}
	[ "${dir##*/}" == 'crystal-compiler' ] && {
		./install.sh
		continue
	}
	./run.sh
done
