#!/bin/bash

DIR=$(dirname $(realpath $0))
cDIR=${DIR##*/}

cmd=(
	docker run
	--rm
	-it
	-v $DIR:/usr/share/code
	-w /usr/share/code
	alpine:crystal
	crystal build src/$cDIR.cr --static
)

"${cmd[@]}"

