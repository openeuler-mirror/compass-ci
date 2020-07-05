FROM debian

MAINTAINER Wu Fenguang <wufengguang@huawei.com>

ENV DEBIAN_FRONTEND noninteractive

COPY root /

RUN	apt-get update && \
	apt-get install -y openssh-server zsh vim rsync git && \
	mkdir /run/sshd

RUN	useradd --create-home --shell /bin/zsh team && \
	passwd --lock root && \
	passwd --lock team && \
	sed -i '1s/bin\/.*sh$/bin\/zsh/' /etc/passwd

