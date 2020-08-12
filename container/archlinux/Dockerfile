# SPDX-License-Identifier: MulanPSL-2.0+

FROM lopsided/archlinux

MAINTAINER Wu Fenguang <wufengguang@huawei.com>

COPY root /
RUN	chmod 755 /etc
RUN	pacman --needed --noprogressbar --noconfirm  -Syu && \
	pacman --needed --noprogressbar --noconfirm  -S bash zsh git openssh rsync make gcc tzdata sudo coreutils util-linux vim gawk
