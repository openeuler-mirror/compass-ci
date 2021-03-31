# Origin: https://hub.docker.com/r/openresty/openresty
# Copyright (C) 2016-2020  Eric D. Evan Wies
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM openresty/openresty:alpine

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories
RUN apk add bash
RUN mkdir -p /var/log/nginx/
RUN adduser lkp -u 1090 -g 1090 -D

COPY ./openresty.sh /usr/local/bin/

CMD ["/usr/local/bin/openresty.sh"]
