# Origin: https://hub.docker.com/r/openresty/openresty
# Copyright (C) 2016-2020  Eric D. Evan Wies
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM result-webdav-base

RUN adduser lkp -u 1090 -g 1090 -D

COPY upload.lua /usr/local/openresty/nginx/conf/lua/upload.lua
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY ./openresty.sh /usr/local/bin/

RUN chown lkp:lkp  /usr/local/openresty/nginx /run /var/run
