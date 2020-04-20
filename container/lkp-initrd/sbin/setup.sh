#!/bin/sh -e

apk add bash gcc make libc-dev findutils cpio gzip
adduser -Du 1090 lkp # lkp group also created
