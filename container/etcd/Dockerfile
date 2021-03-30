# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM alpine:3.13

MAINTAINER Cao Xueliang <caoxl78320@163.com>

ARG VERSION
RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories && \
    apk update && apk add ca-certificates && \
    wget https://repo.huaweicloud.com/etcd/${VERSION}/etcd-${VERSION}-linux-arm64.tar.gz && \
    tar zxvf etcd-${VERSION}-linux-arm64.tar.gz && \
    mv etcd-${VERSION}-linux-arm64/etcd* /bin/ && \
    rm -Rf etcd-${VERSION}-linux-arm64* /var/cache/apk/*

VOLUME /data
