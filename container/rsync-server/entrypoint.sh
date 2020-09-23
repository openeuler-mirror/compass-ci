#!/bin/sh

rsync --daemon

exec "$@"
