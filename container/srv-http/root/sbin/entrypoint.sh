#!/bin/sh

sed -i "s/listen 11300;/listen $LISTEN_PORT;/g" /etc/nginx/conf.d/default.conf

nginx
/usr/sbin/php-fpm7
