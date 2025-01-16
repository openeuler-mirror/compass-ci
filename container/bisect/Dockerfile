# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2024 Huawei Technologies Co., Ltd. All rights reserved.
FROM alpine:latest

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories \
	&& apk update

RUN apk update --no-cache && \
    apk upgrade && \
    apk add --no-cache git coreutils util-linux ruby bash python3 python3-dev py3-pip py3-elasticsearch py3-requests py3-yaml

RUN gem install rest-client

RUN addgroup -S bisect && adduser -S bisect -G bisect

ENV RUNTIME_DIR /home/bisect

RUN mkdir /c && \
    chown -R bisect:bisect /c

WORKDIR $RUNTIME_DIR

COPY --chown=bisect:bisect bisect-task.py $RUNTIME_DIR
