# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM alpine:3.19

MAINTAINER chief <taxcom@tom.com>

ONBUILD RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

ONBUILD RUN apk update
ONBUILD RUN apk add bash zsh git rsync curl crystal shards tzdata sudo \
 yaml-dev openssl-dev ncurses-static g++ make cmake \
 zlib-dev zlib-static openssl-libs-static llvm17 llvm17-dev \
 llvm17-libs llvm17-static musl-dev xz-dev libxml2-dev \
 vim ruby-dev

