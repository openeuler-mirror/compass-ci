# SPDX-License-Identifier: MulanPSL-2.0+

FROM manjaroarm/manjaro-aarch64-base

MAINTAINER Wu Fenguang <wfg@mail.ustc.edu.cn>

COPY root /
RUN	chmod 755 /etc /etc/pacman.d
RUN	pacman --needed --noprogressbar --noconfirm  -Sy && \
	pacman --needed --noprogressbar --noconfirm  -S bash zsh git openssh rsync make gcc tzdata sudo coreutils util-linux vim
RUN	ssh-keygen -t rsa -P '' -f /etc/ssh/ssh_host_rsa_key

CMD ["sh"]
