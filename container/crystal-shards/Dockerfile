# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM alpine:crystal-base

MAINTAINER chief <taxcom@tom.com>

COPY git /usr/local/sbin/git
RUN echo -e "[url \"git://\"]\n\tinsteadOf = https://" >> /etc/gitconfig

COPY shard.yml /usr/share/crystal/app/shard.yml

WORKDIR /usr/share/crystal/app
RUN shards
RUN sed -i 's:data):data, headers\: HTTP\:\:Headers{"Content-Type" => "application/json"}):' /usr/share/crystal/app/lib/elasticsearch-crystal/src/elasticsearch/api/namespace/common.cr; \
sed -i '99s/arguments\[:id]/arguments\[:id]?/'  /usr/share/crystal/app/lib/elasticsearch-crystal/src/elasticsearch/api/actions/index.cr; \
sed -i 's/, Utils.__listify(arguments\[:q].as(String))/ /'  /usr/share/crystal/app/lib/elasticsearch-crystal/src/elasticsearch/api/actions/search.cr;\
sed -i '205a \        params.clear' /usr/share/crystal/app/lib/elasticsearch-crystal/src/elasticsearch/api/actions/search.cr;

COPY shard-amqp.yml /usr/share/crystal/app/shard.yml
RUN shards

CMD ["bash"]

