#!/bin/bash -e

## TODO
# all docker service in directory /c/cci/container, deploy them one by one
# for ele in $(ls /c/cci/container)
# do
#   cd /c/cci/container/$ele
#   ./build.sh
#   ./run.sh
# done
#
#
CONTAINER_PATH='/c/cci/container'
for file in $(ls ${CONTAINER_PATH})
do
	cd ${CONTAINER_PATH}/${file}
	./build.sh
	./run.sh
done
