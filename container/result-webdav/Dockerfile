# SPDX-License-Identifier: MIT
# borrowed-from: https://github.com/jbbodart/alpine-nginx-webdav
FROM nginx:stable-alpine

LABEL maintainer="jbbodart"

VOLUME /srv/result

RUN apk -U upgrade && apk add --no-cache apache2-utils && chmod +w /srv/result

COPY webdav.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD nginx -g "daemon off;"
