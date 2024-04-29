# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM nginx:1.25-alpine3.18

MAINTAINER Cao Xueliang <caoxl78320@163.com>

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories
RUN apk update --no-cache && \
    apk upgrade

RUN adduser lkp -u 1090 -g 1090 -D

RUN chown lkp:lkp /var/cache/nginx /var/run
