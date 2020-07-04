#!/bin/bash -e

[[ $CCI_SRC ]] || export CCI_SRC=$(dirname $(dirname $(dirname $(realpath $0))))
CONTAINER_PATH="$CCI_SRC/container"

git checkout 35ecf8b5b1a743aee939c639ac0696fdc87ef9c5

for dir in $CONTAINER_PATH/*
do
	cur_dir=${dir##*/}
	(
	cd "$dir"
	[ "$cur_dir" == 'scheduler' ] && {
		echo "scheduler-dev first"
		exit
	}
	./build
	[ "$cur_dir" == 'debian' ] || \
	[ "$cur_dir" == 'lkp-initrd' ] || \
	[ "$cur_dir" == 'dracut-initrd' ] || \
	[ "$cur_dir" == 'crystal-base' ] || \
	[ "$cur_dir" == 'crystal-shards' ] || \
	[ "$cur_dir" == 'scheduler-dev' ] && {
		echo "$cur_dir just build, skip!"
		cd "scheduler"
		./build
		./run
		exit
	}
	[ "$cur_dir" == 'crystal-compiler' ] && {
		./install
		exit
	}
	./run
	)&
done
