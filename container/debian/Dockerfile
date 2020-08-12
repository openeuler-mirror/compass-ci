# SPDX-License-Identifier: MulanPSL-2.0+

FROM debian

MAINTAINER Wu Fenguang <wufengguang@huawei.com>

ENV DEBIAN_FRONTEND noninteractive

COPY root /

RUN	apt-get update && \
	apt-get install -y --no-install-recommends apt-utils > /dev/null 2>&1 && \
	apt-get install -y runit openssh-server zsh vim rsync git make gcc g++ tzdata sudo && \
	mkdir -p /run/sshd

