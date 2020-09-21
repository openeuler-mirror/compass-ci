# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM alpine:3.11

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN apk update

RUN apk add --no-cache 'ruby-dev' \
    'g++' 'gcc' 'pcre' 'libevent' 'make' 'git' 'cpio' 'bash'

RUN umask 002 && \
    echo ':sources: ["http://rubygems.org"]' >> ~/.gemrc && \
    gem install rest-client && \
    gem install activesupport && \
    gem install git && \
    gem install json && \
    gem install yaml


ENV SCHED_RUNTIME_DIR /c/cci/scheduler

RUN mkdir -p $SCHED_RUNTIME_DIR && \
    chown -R 1090:1090 /c

WORKDIR $SCHED_RUNTIME_DIR

COPY --chown=1090:1090 scheduler .
COPY --chown=1090:1090 create-job-cpio.sh .
