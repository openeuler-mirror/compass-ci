# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM alpine:scheduler-dev

MAINTAINER Li Ping <1477412247@qq.com>

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN apk update --no-cache && \
    apk add --no-cache 'ruby-dev' \
    'g++' 'gcc' 'pcre' 'libevent' 'make' 'git' 'cpio' 'bash'

ENV UPDATE_REPO_DIR /c/cci/update-repo

RUN mkdir -p $UPDATE_REPO_DIR && \
    chown -R 1090:1090 /c

WORKDIR $UPDATE_REPO_DIR

COPY --chown=1090:1090 updaterepo .
