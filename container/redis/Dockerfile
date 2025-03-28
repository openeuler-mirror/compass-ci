# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM alpine:3.18

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN apk update --no-cache && \
    apk upgrade && \
    apk add --no-cache 'redis'

COPY redis.conf /etc/

VOLUME  /srv/redis
WORKDIR /srv/redis

RUN apk del gcc rpcgen gdb

EXPOSE 6379
