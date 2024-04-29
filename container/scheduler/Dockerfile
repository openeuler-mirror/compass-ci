# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM alpine:scheduler-dev

COPY repositories /etc/apk

RUN apk add --upgrade busybox && \
    apk add --no-cache 'ruby-dev' \
    'g++' 'gcc' 'pcre' 'libevent' 'make' 'git' 'cpio' 'bash' 'util-linux' 'shadow'

RUN groupadd -g 1090 lkp && useradd -m -u 1090 -g 1090 lkp

RUN umask 002 && \
    gem sources -r https://rubygems.org/ -a https://gems.ruby-china.com/ && \
    gem install yaml io-console elasticsearch:7.11.1


ENV SCHED_RUNTIME_DIR /c/cci/scheduler

RUN mkdir -p $SCHED_RUNTIME_DIR 

# fatal: detected dubious ownership in repository at '/c/lkp-tests'
RUN git config --global --add safe.directory /c/lkp-tests && \
	cp /root/.gitconfig /home/lkp/ && \
	chown 1090:1090 /home/lkp/.gitconfig

COPY cbs /c/cbs
COPY lkp-tests /c/lkp-tests
RUN chown -R 1090:1090 /c/cbs /c/lkp-tests && chown -R 750 /c/cbs /c/lkp-tests
WORKDIR $SCHED_RUNTIME_DIR

COPY --chown=1090:1090 scheduler .
COPY --chown=1090:1090 create-job-cpio.sh .
