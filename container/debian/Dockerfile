FROM debian

MAINTAINER Wu Fenguang <wufengguang@huawei.com>

ENV DEBIAN_FRONTEND noninteractive

COPY root /

RUN	apt-get update && \
	apt-get install -y openssh-server zsh vim rsync git make gcc g++ tzdata sudo && \
	mkdir /run/sshd

