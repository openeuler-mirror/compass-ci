#!/bin/bash

cmd=(
    docker run
    --name results-webdav
    -p 3080:80
    -v /srv/webdav:/srv
    -d 
    alpine:webdav

)

"${cmd[@]}"
