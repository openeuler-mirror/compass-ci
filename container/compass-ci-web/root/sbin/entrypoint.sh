#!/bin/sh

ssl_conf="\    ssl_certificate /opt/cert/web-backend.crt;\n\
    ssl_certificate_key /opt/cert/web-backend.key;\n\
    ssl_session_timeout 5m;\n\
    ssl_ciphers BCDHE-RSA-AES128-GCM-SHA256:ECDHE:ECDH:AES:HIGH:!NULL:!aNULL:!MD5:!ADH:!RC4;\n\
    ssl_prefer_server_ciphers on;\n"

if [ -f "/opt/cert/web-backend.key" ] && [ -f "/opt/cert/web-backend.crt" ]; then
	sed -i "s/listen 20030;/listen $LISTEN_PORT ssl;/g" /etc/nginx/nginx.conf
	sed -i "/server_name/a $ssl_conf" /etc/nginx/nginx.conf
else
	sed -i "s/listen 20030;/listen $LISTEN_PORT;/g" /etc/nginx/nginx.conf
fi

nginx -g 'daemon off;'
