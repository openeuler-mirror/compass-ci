# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM alpine:3.18

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN apk update --no-cache && \
    apk upgrade && \
    apk add --no-cache git-daemon && \
    mkdir /git


VOLUME /git/

RUN apk del gcc gdb rpcgen

EXPOSE 9418

CMD ["git", "daemon", "--verbose", "--export-all", "--base-path=/git/", "--reuseaddr", "/git/"]
