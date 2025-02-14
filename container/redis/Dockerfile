# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM redis-base:latest

ARG PASSWD

RUN sed -i "s:# requirepass foobared:requirepass ${PASSWD}:" /etc/redis.conf

VOLUME  /srv/redis
WORKDIR /srv/redis

EXPOSE 6379
CMD ["redis-server", "/etc/redis.conf"]
