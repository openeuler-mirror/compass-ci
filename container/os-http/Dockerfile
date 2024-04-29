# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM nginx:1.22.1-alpine3.17

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories
RUN apk update --no-cache && \
    apk upgrade

COPY root /

RUN adduser lkp -u 1090 -g 1090 -D

RUN chown lkp:lkp /var/cache/nginx /var/run
