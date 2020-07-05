FROM lopsided/archlinux

MAINTAINER Wu Fenguang <wufengguang@huawei.com>

COPY root /
RUN	pacman --needed --noprogressbar --noconfirm  -Syu && \
	pacman --needed --noprogressbar --noconfirm  -S bash zsh git openssh rsync make gcc tzdata sudo coreutils util-linux vim gawk
