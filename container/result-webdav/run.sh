#!/bin/bash

cmd=(
    docker run
    --privileged=true
    --name result-webdav
    -p 3080:80
    -v /srv/result:/srv/result
    -d 
    result-webdav
)

"${cmd[@]}"
