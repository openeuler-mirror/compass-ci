# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM debian:buster

MAINTAINER Wu Fenguang <wfg@mail.ustc.edu.cn>

ENV DEBIAN_FRONTEND noninteractive

COPY root /

RUN	sed -i "s/^exit [0-9]*/exit 0/" /usr/sbin/policy-rc.d
RUN	apt-get clean && \
	apt-get update && \
	apt-get install -y --no-install-recommends apt-utils > /dev/null 2>&1 && \
	apt-get install -y -o APT::Immediate-Configure=false runit openssh-server zsh vim rsync git make gcc g++ tzdata sudo && \
	mkdir -p /run/sshd

