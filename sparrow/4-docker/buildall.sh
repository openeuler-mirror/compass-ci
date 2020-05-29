#!/bin/bash -e

[[ $CCI_SRC ]] || export CCI_SRC=$(dirname $(dirname $(dirname $(realpath $0))))
CONTAINER_PATH="$CCI_SRC/container"

for dir in $CONTAINER_PATH/*
do
	cd "$dir"
	./build.sh
	[ "${dir##*/}" == 'crystal-compiler' ] && {
		./install.sh
		continue
	}
	./run.sh
done
