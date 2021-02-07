# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM debian

MAINTAINER Wu Fenguang <wfg@mail.ustc.edu.cn>

ADD bin /usr/local/bin
COPY conf/sources.list* /etc/apt/
COPY conf/add-modules.conf /etc/dracut.conf.d/
WORKDIR /usr/local/bin

RUN setup-dracut.sh
