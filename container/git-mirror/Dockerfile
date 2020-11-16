# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM alpine:3.8
MAINTAINER Li Yuanchao <lyc163mail@163.com>

ADD kill-parent.sh /

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN apk update && \
    echo ':sources: ["http://rubygems.org"]' >> ~/.gemrc && \
    apk upgrade && \
    apk add --no-cache git && \
    apk add ruby-dev make gcc g++

RUN umask 002 && \
    gem install bunny json PriorityQueue elasticsearch --no-rdoc --no-ri

