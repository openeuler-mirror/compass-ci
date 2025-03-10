# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM alpine:3.21

MAINTAINER Cao Xueliang <caoxl78320@163.com>

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN apk add gcc g++ make libffi-dev openssl-dev openssl-libs-static libcrypto3 libtool yaml-dev yaml-static zlib-static zlib-dev crystal shards && shards init
