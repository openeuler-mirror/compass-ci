# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM node:10.21.0-alpine
MAINTAINER Li Yuanchao <lyc163mail@163.com>

ADD root /

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN apk update && \
    apk upgrade && \
    apk add --no-cache git && \
    apk add npm ruby-dev

RUN gem sources -r https://rubygems.org/ -a https://gems.ruby-china.com/

RUN npm install git-webhook-handler && \
    gem install bunny

