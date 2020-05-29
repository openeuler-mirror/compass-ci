#!/bin/bash -e

CONTAINER_PATH='/c/cci/container'
for file in $(ls ${CONTAINER_PATH})
do
	cd ${CONTAINER_PATH}/${file}
	./build.sh
	[ 'crystal-compiler' == "$file" ] && ./install.sh && next
	./run.sh
done


