# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM alpine:3.11

MAINTAINER Bai Jing <799286817@qq.com>

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN apk update
RUN apk add gcc make g++ bash ipmitool
RUN wget https://ghproxy.com/https://github.com/bstansell/conserver/releases/download/v8.2.4/conserver-8.2.4.tar.gz && \
    tar -xf conserver-8.2.4.tar.gz && \
    cd conserver-8.2.4 && \
    ./configure && make && make install && mkdir -p /var/consoles/

RUN echo "console         782/tcp         conserver" >> /etc/services
COPY ipmi-sol /usr/local/bin/
COPY conserver /usr/local/bin/
COPY conserver.cf /etc/conserver.cf
ENTRYPOINT ["/usr/local/bin/conserver"]
