#!/bin/bash

DIR=$(dirname $(realpath $0))
sudo ln -s $DIR/run.sh /usr/local/bin/crystal
