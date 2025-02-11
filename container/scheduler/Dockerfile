# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM alpine:scheduler-dev

COPY repositories /etc/apk

RUN apk add --upgrade busybox && \
    apk add --no-cache 'ruby-dev' \
    'g++' 'gcc' 'pcre' 'libevent' 'make' 'git' 'cpio' 'bash' 'util-linux' 'shadow' 'openssl' 'rpm2cpio' 'wget' 'coreutils'

RUN groupadd -g 1090 lkp && useradd -m -u 1090 -g 1090 lkp

RUN umask 002 && \
    gem sources -r https://rubygems.org/ -a https://gems.ruby-china.com/ && \
    gem install yaml io-console elasticsearch:7.11.1

COPY compass-ci	/c/compass-ci
COPY lkp-tests /c/lkp-tests

RUN chown -R 1090:1090 /c/compass-ci /c/lkp-tests && chown -R 750 /c/compass-ci

ENV SCHED_RUNTIME_DIR /c/cci/scheduler
RUN mkdir -p $SCHED_RUNTIME_DIR 
WORKDIR $SCHED_RUNTIME_DIR

COPY scheduler .
COPY create-job-cpio.sh .

RUN chown 1090:1090 /c/cci/scheduler/scheduler /c/cci/scheduler/create-job-cpio.sh
