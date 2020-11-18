# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM lopsided/archlinux

MAINTAINER Wu Fenguang <wfg@mail.ustc.edu.cn>

ARG	ARCH

COPY 	root/$ARCH /

RUN	chmod 755 /etc

RUN	pacman --needed --noprogressbar --noconfirm  -Syu && \
	pacman --needed --noprogressbar --noconfirm  -S bash zsh git openssh rsync make gcc tzdata sudo coreutils util-linux vim gawk
