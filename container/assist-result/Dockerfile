# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM alpine:3.11

MAINTAINER Cao Xueliang <caoxl78320@163.com>

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories && \
    apk update --no-cache && \
    apk add --no-cache 'ruby-dev' 'ruby-etc' \
    'g++' 'gcc' 'pcre' 'libevent' 'make' 'git' 'bash' 'grep' 'coreutils' 'curl' 'util-linux'

RUN umask 002 && \
    gem sources -r https://rubygems.org/ -a https://gems.ruby-china.com/ && \
    gem install rest-client activesupport:6.1.4.4 json yaml elasticsearch:7.11.1 sinatra puma terminal-table
