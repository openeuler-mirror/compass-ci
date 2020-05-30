# SPDX-License-Identifier: MIT
# borrowed-from: https://github.com/jbbodart/alpine-nginx-webdav
FROM nginx:stable-alpine

LABEL maintainer="jbbodart"

RUN apk -U upgrade && apk add --no-cache apache2-utils && adduser lkp -u 1090 -g 1090 -D 

COPY webdav.conf /etc/nginx/conf.d/default.conf

COPY entrypoint.sh /

RUN chmod +x entrypoint.sh

EXPOSE 80

CMD /entrypoint.sh
