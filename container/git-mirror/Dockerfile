# SPDX-License-Identifier: MulanPSL-2.0+

FROM alpine:3.8

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN apk update && \
    apk upgrade && \
    apk add --no-cache git && \
    apk add ruby-dev make gcc g++

RUN umask 002 && \
    gem install bunny json PriorityQueue --no-rdoc --no-ri

