#!/bin/bash -e

[[ $CCI_SRC ]] || export CCI_SRC=$(dirname $(dirname $(dirname $(realpath $0))))
CONTAINER_PATH="$CCI_SRC/container"

for dir in $CONTAINER_PATH/*
do
	cur_dir=${dir##*/}
	cd "$dir"
	./build.sh
	[ "$cur_dir" == 'debian' ] || \
	[ "$cur_dir" == 'lkp-initrd' ] || \
	[ "$cur_dir" == 'dracut-initrd' ] || \
	[ "$cur_dir" == 'crystal-base' ] || \
	[ "$cur_dir" == 'scheduler-dev' ] && {
		echo "$cur_dir just build, skip!"
		continue
	}
	[ "$cur_dir" == 'crystal-compiler' ] && {
		./install.sh
		continue
	}
	./run.sh
done
