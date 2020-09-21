# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM alpine:3.11

MAINTAINER Wu Fenguang <wfg@mail.ustc.edu.cn>

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

COPY sbin /usr/local/sbin
RUN /usr/local/sbin/setup.sh

WORKDIR /root
