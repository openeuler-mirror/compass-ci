# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM alpine:crystal-base

MAINTAINER chief <taxcom@tom.com>

COPY git /usr/local/sbin/git
# RUN echo -e "[url \"git://\"]\n\tinsteadOf = https://" >> /etc/gitconfig

COPY shard.yml /usr/share/crystal/app/shard.yml

WORKDIR /usr/share/crystal/app
RUN echo "mkdir -p /root/.cache/shards/github.com" > dl.sh && \
    echo "cd /root/.cache/shards/github.com" >> dl.sh && \
    awk '/github: / { split($2, dir, "/"); print "mkdir "dir[1]"; git -C "dir[1]" clone --bare --depth=1 https://github.com/"$2 }' shard.yml >> dl.sh && \
    echo "exit 0" >> dl.sh
RUN sh dl.sh
RUN shards || shards || shards || shards || shards || shards || shards || shards || shards
RUN sed -i 's:data):data, headers\: HTTP\:\:Headers{"Content-Type" => "application/json"}):' /usr/share/crystal/app/lib/elasticsearch-crystal/src/elasticsearch/api/namespace/common.cr; \
sed -i '99s/arguments\[:id]/arguments\[:id]?/'  /usr/share/crystal/app/lib/elasticsearch-crystal/src/elasticsearch/api/actions/index.cr; \
sed -i 's/, Utils.__listify(arguments\[:q].as(String))/ /'  /usr/share/crystal/app/lib/elasticsearch-crystal/src/elasticsearch/api/actions/search.cr;\
sed -i '205a \        params.clear' /usr/share/crystal/app/lib/elasticsearch-crystal/src/elasticsearch/api/actions/search.cr;

CMD ["bash"]

