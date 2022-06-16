# meaning
SRV_HTTP_RESULT_HOST and SRV_HTTP_RESULT_POST specifies the web address for accessing test result

SRV_HTTP_RESULT_HOST default is https://api.compass-ci.openeuler.org

SRV_HTTP_RESULT_HOST default is 20007

# where use it
compass-ci/container/srv-http/start-result
    start container with LISTEN_PORT:20007
```
cmd=(
        docker run
        --restart=always
        --name srv-http-result
        -e LISTEN_PORT=20007
        -p 20007:20007
        -v /srv/result:/srv/result:ro
        -v /etc/localtime:/etc/localtime:ro
        $(mount_ssl)
        -d
        srv-http
)

"${cmd[@]}"
```

compass-ci/container/srv-http/root/sbin/entrypoint.sh
    use $LISTEN_PORT for nginx conf
```
if [ -f "/opt/cert/web-backend.key" ] && [ -f "/opt/cert/web-backend.crt" ]; then
        sed -i "s/listen 11300;/listen $LISTEN_PORT ssl;/g" /etc/nginx/conf.d/default.conf
        sed -i "/server_name/a $ssl_conf" /etc/nginx/conf.d/default.conf
else
        sed -i "s/listen 11300;/listen $LISTEN_PORT;/g" /etc/nginx/conf.d/default.conf
fi

nginx
/usr/sbin/php-fpm7
```
