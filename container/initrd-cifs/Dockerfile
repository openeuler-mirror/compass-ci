# Origin: https://github.com/Stanback/alpine-samba
# Copyright (C) 2016-2020  Eric D. Stanback
# SPDX-License-Identifier: GPL-3.0

FROM alpine:3.18

MAINTAINER Xiao Shenwei <xiaoshenwei96@163.com>

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories
RUN adduser -u 1090 -D lkp
RUN apk update --no-cache && \
    apk upgrade && \
    apk add --update --no-cache \
    samba-common-tools \
    samba-client \
    samba-server \
    bash
RUN rm -rf /var/cache/apk/*

COPY ./smb.conf /etc/samba/
RUN chown -R lkp:lkp /var/log /usr/sbin/smbd 
EXPOSE 446/tcp

ENTRYPOINT ["smbd", "--foreground", "--no-process-group", "--debug-stdout"]
