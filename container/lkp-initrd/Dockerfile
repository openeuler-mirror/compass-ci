# SPDX-License-Identifier: MulanPSL-2.0+

FROM alpine:3.11

MAINTAINER Wu Fenguang <wufengguang@huawei.com>

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

COPY sbin /usr/local/sbin
RUN /usr/local/sbin/setup.sh

WORKDIR /root
