# Origin: https://github.com/git-cloner/gitcache
# Copyright (C) 2019-2020  Eric D.little51
# SPDX-License-Identifier: GPL-3.0

FROM golang:alpine

ENV GO111MODULE on
ENV GOPROXY https://goproxy.cn


RUN apk add --no-cache git && \
    git clone https://github.com/git-cloner/gitcache /gitcache && \
    cd /gitcache && go build

ENTRYPOINT ["/gitcache/gitcache"]
