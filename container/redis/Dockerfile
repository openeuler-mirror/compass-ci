# SPDX-License-Identifier: MulanPSL-2.0+

FROM alpine:3.11

RUN sed -i.origin 's|http://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN apk add --no-cache 'redis'

RUN sed -i 's:dir /var/lib/redis:dir /srv/redis:' /etc/redis.conf; \
    sed -i 's:protected-mode yes:protected-mode no:' /etc/redis.conf; \
    sed -i 's:bind 127.0.0.1:#bind 127.0.0.1:' /etc/redis.conf

VOLUME  /srv/redis
WORKDIR /srv/redis

EXPOSE 6379
CMD ["redis-server", "/etc/redis.conf"]

