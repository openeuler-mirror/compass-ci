#!/bin/bash

DIR=$(dirname $(realpath $0))
cDIR=${DIR##*/}

cmd=(
	docker run
	--rm
	-it
	-e USER=$USER
	-v $DIR:/usr/share/code
	-w /usr/share/code
	alpine:crystal
	sh -c "shards install && chown -R $USER:$USER lib"
)

"${cmd[@]}"

