# Refer to: https://github.com/tuna/tunasync
# License: GPL-3.0
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# SPDX-License-Identifier: MulanPSL-2.0+

FROM alpine:3.15

MAINTAINER Wang Yong <wangyong0117@qq.com>

ARG ARCH

COPY setup.sh /

COPY etc /etc

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories \
	&& apk update --no-cache \
	&& apk add --no-cache go rsync\
	&& mkdir -p /tmp/log \
	&& chmod +x /setup.sh \
	&& wget https://ghproxy.com/https://github.com/tuna/tunasync/releases/download/v0.8.0/tunasync-linux-${ARCH}-bin.tar.gz \
	&& tar -xf tunasync-linux-${ARCH}-bin.tar.gz -C /usr/bin \
	&& rm -f tunasync-linux-${ARCH}-bin.tar.gz

EXPOSE 32345
EXPOSE 32346

CMD ["/bin/sh", "-c", "umask 002 && /setup.sh"]
