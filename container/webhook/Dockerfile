# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM node:20-alpine
MAINTAINER Li Yuanchao <lyc163mail@163.com>

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN apk update --no-cache && \
    apk upgrade && \
    apk add --no-cache git && \
    apk add --no-cache npm ruby-dev make gcc g++

COPY compass-ci/container/webhook/root /js

WORKDIR /js

RUN gem sources -r https://rubygems.org/ -a https://gems.ruby-china.com/

RUN npm install git-webhook-handler path-parse@">=1.0.7" ansi-regex@">=5.0.1" && \
    gem install bunny

RUN apk del gdb gcc rpcgen
