# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM alpine:3.11

MAINTAINER Wu Zhende <wuzhende666@163.com>

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN apk update

RUN apk add --no-cache 'ruby-dev' \
    'g++' 'gcc' 'pcre' 'libevent' 'make' 'git' 'cpio' 'bash'

RUN umask 002 && \
    echo ':sources: ["http://rubygems.org"]' >> ~/.gemrc && \
    gem install fluentd && \
    gem install fluent-plugin-rabbitmq && \
    gem install fluent-plugin-elasticsearch && \
    gem install fluent-plugin-tail-ex && \
    gem install fluent-plugin-tail-multiline && \
    gem install json && \
    gem install async && \
    gem install webrick && \
    gem install io-console && \
    gem install etc

EXPOSE 24224 24224/udp
