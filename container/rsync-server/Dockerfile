# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM alpine:3.11

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN apk update

RUN apk add --no-cache rsync openssh  \
	&& rm -rf /var/cache/apk/* \
	&& adduser lkp -u 1090 -g 1090 -D

COPY rsyncd.conf /etc/rsyncd.conf
COPY entrypoint.sh /

ENTRYPOINT ["/entrypoint.sh"]

CMD ["sh"]  
