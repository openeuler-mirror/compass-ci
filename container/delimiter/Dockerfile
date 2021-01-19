# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM alpine:3.13

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories && \
    apk update && \
    apk add --no-cache 'ruby-dev' \
    'g++' 'gcc' 'pcre' 'libevent' 'make' 'git' 'bash' 'grep' 'coreutils' 'curl' 'util-linux'

RUN umask 002 && \
    gem sources -r https://rubygems.org/ -a https://gems.ruby-china.com/ && \
    gem install rest-client activesupport git json yaml elasticsearch faye-websocket terminal-table mail io-console
