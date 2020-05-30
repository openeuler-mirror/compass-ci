#!/bin/sh

umask 002

sed -i 's/user  nginx/user  lkp/g' /etc/nginx/nginx.conf

nginx -g "daemon off;"
