# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2024 Huawei Technologies Co., Ltd. All rights reserved.
FROM alpine:latest

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories \
	&& apk update

RUN apk update --no-cache && \
    apk upgrade && \
    apk add --no-cache git && \
    apk add --no-cache coreutils util-linux ruby bash python3 python3-dev py3-pip

RUN pip install --break-system-packages --upgrade pip -i https://mirrors.aliyun.com/pypi/simple && \
    pip3 install --break-system-packages PyYAML requests elasticsearch -i https://mirrors.aliyun.com/pypi/simple && \
    gem install rest-client

RUN addgroup -S bisect && adduser -S bisect -G bisect

ENV RUNTIME_DIR /home/bisect

RUN mkdir /c && \
    chown -R bisect:bisect /c

WORKDIR $RUNTIME_DIR

COPY --chown=bisect:bisect bisect-task.py $RUNTIME_DIR
