# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM alpine:3.11

MAINTAINER Wu Zhende <wuzhende666@163.com>

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN apk update && \
    apk add --no-cache 'ruby-dev' \
    'g++' 'gcc' 'pcre' 'libevent' 'make' 'git' 'cpio' 'bash'

RUN umask 002 && \
    gem sources -r https://rubygems.org/ -a https://gems.ruby-china.com/ && \
    gem install rest-client activesupport git json yaml

ENV LIFECYCLE_RUNTIME_DIR /c/cci/lifecycle

RUN mkdir -p $LIFECYCLE_RUNTIME_DIR && \
    chown -R 1090:1090 /c

WORKDIR $LIFECYCLE_RUNTIME_DIR

COPY --chown=1090:1090 lifecycle .
