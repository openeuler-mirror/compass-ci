# Origin: https://github.com/Stanback/alpine-samba
# Copyright (C) 2016-2020  Eric D. Stanback
# SPDX-License-Identifier: GPL-3.0

FROM alpine:edge

RUN sed -i.origin 's|dl-cdn.alpinelinux.org|mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN adduser -u 1090 -D lkp

RUN apk add --update \
    samba-common-tools \
    samba-client \
    samba-server \
    bash \
    && rm -rf /var/cache/apk/*

EXPOSE 445/tcp

ENTRYPOINT ["smbd", "--foreground", "--no-process-group", "--log-stdout"]
