# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM alpine:3.8
MAINTAINER Li Yuanchao <lyc163mail@163.com>

ADD git-askpass.sh /usr/local/bin/
RUN adduser -u 1090 -D lkp

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN apk update && \
    apk upgrade && \
    apk add --no-cache git tini && \
    apk add ruby-dev make gcc g++ openssh file

RUN umask 002 && \
    gem sources -r https://rubygems.org/ -a https://gems.ruby-china.com/ && \
    gem install bunny json PriorityQueue elasticsearch --no-rdoc --no-ri

ENTRYPOINT ["/sbin/tini", "--"]
