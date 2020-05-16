#!/bin/bash

cmd=(
    docker run
    --name result-webdav
    -p 3080:80
    -v /srv/result:/result
    -d 
    result-webdav
)

"${cmd[@]}"
