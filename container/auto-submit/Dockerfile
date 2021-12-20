# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM alpine:3.11

RUN adduser -u 1090 -D lkp
RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN apk update && \
    apk upgrade && \
    apk add --no-cache git && \
    apk add ruby-dev make gcc g++ util-linux bash

RUN gem sources -r https://rubygems.org/ -a https://gems.ruby-china.com/

RUN umask 002 && \
    gem install bunny json activesupport:6.1.4.4 git rest-client io-console elasticsearch md5sum base64
