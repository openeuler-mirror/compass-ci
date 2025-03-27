# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM alpine:scheduler-dev

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories && \
    apk update --no-cache && \
    apk upgrade && \
    apk add --no-cache 'ruby-dev' \
    'g++' 'gcc' 'pcre' 'libevent' 'make' 'git' 'cpio' 'bash' 'grep'

RUN umask 002 && \
    gem sources -r https://rubygems.org/ -a https://gems.ruby-china.com/ && \
    gem install securerandom:0.3.2 rest-client activesupport:7.1.5.1 git:1.19.0 json yaml elasticsearch:7.11.1 terminal-table

ENV RUNTIME_DIR /c/cci/extract

RUN adduser -u 1090 -D lkp

RUN mkdir -p $RUNTIME_DIR && \
    chown -R 1090:1090 /c

COPY compass-ci /c/compass-ci
COPY lkp-tests /c/lkp-tests

RUN chown -R 1090:1090 /c/compass-ci /c/lkp-tests&& chown -R 750 /c/compass-ci /c/lkp-tests

RUN apk del gcc rpcgen gdb

WORKDIR $RUNTIME_DIR

COPY --chown=1090:1090 extract-stats .
