# borrowed-from: https://github.com/jbbodart/alpine-nginx-webdav
FROM nginx:stable-alpine

LABEL maintainer="jbbodart"

VOLUME /srv

RUN apk -U upgrade && apk add --no-cache apache2-utils && chmod -R 777 /srv 

COPY webdav.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD nginx -g "daemon off;"
