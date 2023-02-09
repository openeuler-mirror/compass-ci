# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM alpine:3.13

MAINTAINER Cao Xueliang <caoxl78320@163.com>

ARG VERSION
ARG ARCH
RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories && \
    apk update && apk add ca-certificates && \
    wget https://repo.huaweicloud.com/etcd/${VERSION}/etcd-${VERSION}-linux-${ARCH}.tar.gz && \
    tar zxvf etcd-${VERSION}-linux-${ARCH}.tar.gz && \
    mv etcd-${VERSION}-linux-${ARCH}/etcd* /bin/ && \
    rm -Rf etcd-${VERSION}-linux-${ARCH}* /var/cache/apk/*

VOLUME /data

COPY etcd_compact.sh /
COPY entry.sh /
RUN echo '0 0 * * * /etcd_compact.sh > /etcd_compact.log 2>&1' >> /var/spool/cron/crontabs/root

ENTRYPOINT ["/entry.sh"]
