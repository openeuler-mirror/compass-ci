#!/bin/bash -e

CONTAINER_PATH='/c/cci/container'
for file in $(ls ${CONTAINER_PATH})
do
	cd ${CONTAINER_PATH}/${file}
	./build.sh
	[ "$file" == 'crystal-compiler' ] && {
		./install.sh
		continue
	}
	./run.sh
done


