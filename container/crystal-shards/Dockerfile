# SPDX-License-Identifier: MulanPSL-2.0+

FROM alpine:crystal-base

MAINTAINER chief <tongqunfeng@huawei.com>

copy shard.yml /usr/share/crystal/app/shard.yml

WORKDIR /usr/share/crystal/app
RUN shards
RUN sed -i 's:data):data, headers\: HTTP\:\:Headers{"Content-Type" => "application/json"}):' /usr/share/crystal/app/lib/elasticsearch-crystal/src/elasticsearch/api/namespace/common.cr;

copy shard-amqp.yml /usr/share/crystal/app/shard.yml
RUN shards

CMD ["bash"]

