# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2024 Huawei Technologies Co., Ltd. All rights reserved.
FROM alpine

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories \
	&& apk update

RUN apk update --no-cache && \
    apk upgrade && \
    apk add --no-cache git coreutils util-linux ruby bash python3 python3-dev py3-pip \
    gnuplot \
    py3-requests py3-yaml py3-httpx py3-flask py3-flask-cors py3-numpy py3-schedule \
    supervisor \
    cpio

RUN gem install rest-client base64
RUN /usr/bin/python3 -m pip install mysql-connector-python --break-system-packages -i https://mirrors.aliyun.com/pypi/simple/
RUN addgroup -g 30117 -S bisect && addgroup -g 1090 -S lkp && adduser -u 30116 -S bisect -G bisect -G lkp

ENV WORK_DIR /c/bisect
ENV RESULT_DIR /result/bisect
ENV RUNTIME_DIR /c

RUN mkdir $RUNTIME_DIR && \
    chown -R bisect:bisect $RUNTIME_DIR && \
    mkdir -p $RESULT_DIR/logs/consumer $RESULT_DIR/logs/producer \
             $RESULT_DIR/logs/api $RESULT_DIR/logs/commit-service \
             $RESULT_DIR/logs/performance && \
    chown -R bisect:bisect $RESULT_DIR

WORKDIR $WORK_DIR
USER bisect

COPY --chown=bisect:bisect compass-ci $RUNTIME_DIR/compass-ci
COPY --chown=bisect:bisect lkp-tests $RUNTIME_DIR/lkp-tests

