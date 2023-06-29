# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM alpine:3.11

ARG PASSWD

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN apk add --no-cache 'redis'

RUN sed -i 's:dir /var/lib/redis:dir /srv/redis:' /etc/redis.conf; \
    sed -i 's:protected-mode yes:protected-mode no:' /etc/redis.conf; \
    sed -i 's:bind 127.0.0.1:#bind 127.0.0.1:' /etc/redis.conf; \
    sed -i "s:# requirepass foobared:requirepass ${PASSWD}:" /etc/redis.conf

VOLUME  /srv/redis
WORKDIR /srv/redis

EXPOSE 6379
CMD ["redis-server", "/etc/redis.conf"]

