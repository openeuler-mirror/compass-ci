#!/bin/bash

DIR=$(dirname $(realpath $0))
cDIR=${DIR##*/}

cmd=(
	docker run
	--rm
	-it
	-u $UID
	-v $DIR:/usr/share/code
	-w /usr/share/code
	alpine:scheduler-dev
	sh -c "crystal build src/$cDIR.cr"
)

"${cmd[@]}"

