# Origin: https://hub.docker.com/r/openresty/openresty
# Copyright (C) 2016-2020  Eric D. Evan Wies
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM openresty/openresty:1.21.4.1-alpine-fat

ARG ARCH

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories
RUN apk update --no-cache && \
    apk upgrade && \
    apk add --no-cache bash rpm pinentry gpg gpg-agent gcc lua-dev git
RUN mkdir -p /var/log/nginx/
RUN adduser lkp -u 1090 -g 1090 -D

COPY upload.lua /usr/local/openresty/nginx/conf/lua/upload.lua
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY openresty.sh /usr/local/bin/

RUN chown lkp:lkp  /usr/local/openresty/nginx /run /var/run

RUN git clone https://github.com/PythonEngineer007/lua-resty-redis-cluster.git /lua-resty-redis-cluster

RUN cp /lua-resty-redis-cluster/lib/redis_slot.c /usr/local/openresty/lualib/

RUN cp /lua-resty-redis-cluster/lib/resty/rediscluster.lua /usr/local/openresty/lualib/resty/

RUN cd /usr/local/openresty/lualib && gcc redis_slot.c -fPIC -shared -o libredis_slot.so

RUN rm -rf /lua-resty-redis-cluster

RUN apk del rpcgen gdb

CMD ["sh", "-c", "umask 002 && /usr/local/bin/openresty.sh"]
