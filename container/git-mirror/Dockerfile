# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM alpine:3.18
MAINTAINER Li Yuanchao <lyc163mail@163.com>

COPY git-askpass.sh /usr/local/bin/
RUN adduser -u 1090 -D lkp

COPY repositories /etc/apk/repositories

RUN apk update --no-cache && \
    apk upgrade && \
    apk add -f --no-cache git tini && \
    apk add -f --no-cache ruby-dev=2.5.8-r0 make gcc=6.4.0-r9 g++=6.4.0-r9 openssh file

RUN umask 002 && \
    gem sources -r https://rubygems.org/ -a https://mirrors.aliyun.com/rubygems/ &&\
    gem install bunny:2.19.0 json PriorityQueue elasticsearch:7.11.1 --no-document

COPY cbs /c/cbs

RUN chown -R 1090:lkp /c/cbs && chown -R 750 /c/cbs

RUN apk del gcc rpcgen gdb

WORKDIR /c/cbs/sbin

ENTRYPOINT ["/sbin/tini", "--"]
