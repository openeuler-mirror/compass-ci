#!/bin/bash -e

cd /c

git clone https://github.com/crystal-ameba/ameba

cd ameba

crystal build src/cli.cr -o bin/ameba

sudo ln -s /c/ameba/bin/ameba /usr/local/bin/ameba
