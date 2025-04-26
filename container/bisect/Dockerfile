# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2024 Huawei Technologies Co., Ltd. All rights reserved.
FROM alpine:latest

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories \
	&& apk update

RUN apk update --no-cache && \
    apk upgrade && \
    apk add --no-cache git coreutils util-linux ruby bash python3 python3-dev py3-pip py3-elasticsearch py3-requests py3-yaml py3-httpx py3-flask

RUN gem install rest-client

RUN addgroup -S bisect && adduser -S bisect -G bisect

ENV WORK_DIR /home/bisect
ENV RUNTIME_DIR /c

RUN mkdir $RUNTIME_DIR && \
    chown -R bisect:bisect $RUNTIME_DIR

WORKDIR $WORK_DIR

COPY --chown=bisect:bisect bisect-task.py $WORK_DIR
COPY --chown=bisect:bisect compass-ci $RUNTIME_DIR/compass-ci
COPY --chown=bisect:bisect lkp-tests $RUNTIME_DIR/lkp-tests

