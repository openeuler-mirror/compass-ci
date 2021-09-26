# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM debian:buster

MAINTAINER Wu Fenguang <wfg@mail.ustc.edu.cn>

ADD bin /usr/local/bin
ADD modules.d /usr/lib/modules.d
COPY modules.d/90lkp /usr/lib/dracut/modules.d/90lkp
COPY conf/sources.list* /etc/apt/
COPY conf/add-modules.conf /etc/dracut.conf.d/
WORKDIR /usr/local/bin

RUN setup-dracut.sh
