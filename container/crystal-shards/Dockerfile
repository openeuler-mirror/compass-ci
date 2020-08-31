# SPDX-License-Identifier: MulanPSL-2.0+

FROM alpine:crystal-base

MAINTAINER chief <tongqunfeng@huawei.com>

ARG GITCACHE_HOST
ARG GITCACHE_PORT
RUN [ -n "$GITCACHE_HOST" ] && echo -e "[url \"http://$GITCACHE_HOST:${GITCACHE_PORT:-5000}/\"]\n\tinsteadOf = https://" >> /etc/gitconfig

copy shard.yml /usr/share/crystal/app/shard.yml

WORKDIR /usr/share/crystal/app
RUN shards
RUN sed -i 's:data):data, headers\: HTTP\:\:Headers{"Content-Type" => "application/json"}):' /usr/share/crystal/app/lib/elasticsearch-crystal/src/elasticsearch/api/namespace/common.cr; \
sed -i '99s/arguments\[:id]/arguments\[:id]?/'  /usr/share/crystal/app/lib/elasticsearch-crystal/src/elasticsearch/api/actions/index.cr; \
sed -i 's/, Utils.__listify(arguments\[:q].as(String))/ /'  /usr/share/crystal/app/lib/elasticsearch-crystal/src/elasticsearch/api/actions/search.cr;\
sed -i '205a \        params.clear' /usr/share/crystal/app/lib/elasticsearch-crystal/src/elasticsearch/api/actions/search.cr;

copy shard-amqp.yml /usr/share/crystal/app/shard.yml
RUN shards

CMD ["bash"]

