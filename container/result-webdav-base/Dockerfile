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

RUN git clone https://gh-proxy.com/https://github.com/PythonEngineer007/lua-resty-redis-cluster.git /lua-resty-redis-cluster

RUN cp /lua-resty-redis-cluster/lib/redis_slot.c /usr/local/openresty/lualib/

RUN cp /lua-resty-redis-cluster/lib/resty/rediscluster.lua /usr/local/openresty/lualib/resty/

RUN cd /usr/local/openresty/lualib && gcc redis_slot.c -fPIC -shared -o libredis_slot.so

RUN rm -rf /lua-resty-redis-cluster

RUN if [ "$ARCH" = "aarch64" ]; \
then wget https://gitee.com/openeuler/signatrust/releases/download/v1.0.0-rc.2/client_linux_aarch64_musl.tar.gz -P / &>/dev/null && \
     cd / && \
     tar xvf client_linux_aarch64_musl.tar.gz && \
     mv client /usr/bin && \
     rm -f client_linux_aarch64_musl.tar.gz; \
elif [ "$ARCH" = "x86_64" ]; \
then wget https://gitee.com/openeuler/signatrust/releases/download/v1.0.0-rc.2/client_linux_x86_64.tar.gz -P / &>/dev/null && \
     cd / && \
     tar xvf client_linux_x86_64.tar.gz && \
     mv client /usr/bin && \
     rm -f client_linux_x86_64.tar.gz; \
fi

RUN apk del rpcgen gdb
