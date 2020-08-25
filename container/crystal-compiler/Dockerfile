# SPDX-License-Identifier: MulanPSL-2.0+

FROM alpine:3.11

MAINTAINER caoxl

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN apk add gcc g++ make libffi-dev openssl-dev libtool yaml-dev crystal shards && shards init


