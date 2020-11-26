# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

ARG	BASE_IMAGE

FROM	${BASE_IMAGE}

MAINTAINER Wu Fenguang <wfg@mail.ustc.edu.cn>
ARG	ARCH

COPY	root/${ARCH} /
RUN	chmod 755 /etc /etc/pacman.d
RUN	pacman --needed --noprogressbar --noconfirm  -Syu && \
	pacman --needed --noprogressbar --noconfirm  -S bash zsh git openssh rsync make gcc tzdata sudo coreutils util-linux vim
RUN	ssh-keygen -t rsa -P '' -f /etc/ssh/ssh_host_rsa_key

CMD ["sh"]
