# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

ARG BASE_IMAGE
FROM $BASE_IMAGE

ARG MEMORY
ARG USER
ARG PASSWORD

# docker image borrowed from hub.docker.com/r/gagara/elasticsearch-oss-arm64

MAINTAINER Wu Zhende <wuzhende666@163.com>

RUN sed -i 's:#network.host\: _site_:network.host\: 0.0.0.0:' /usr/share/elasticsearch/config/elasticsearch.yml && \
    sed -i '$a path.data: /srv/es/logging-es' /usr/share/elasticsearch/config/elasticsearch.yml && \
    sed -i '$a node.name: node-1' /usr/share/elasticsearch/config/elasticsearch.yml && \
    sed -i '$a cluster.initial_master_nodes: ["node-1"]' /usr/share/elasticsearch/config/elasticsearch.yml && \
    sed -i '$a indices.memory.index_buffer_size: 20%' /usr/share/elasticsearch/config/elasticsearch.yml && \
    sed -i '$a thread_pool.write.queue_size: 2000' /usr/share/elasticsearch/config/elasticsearch.yml && \
    sed -i '$a xpack.security.enabled: true' /usr/share/elasticsearch/config/elasticsearch.yml && \
    sed -i '$a xpack.license.self_generated.type: basic' /usr/share/elasticsearch/config/elasticsearch.yml && \
    sed -i '$a xpack.security.transport.ssl.enabled: true' /usr/share/elasticsearch/config/elasticsearch.yml && \
    sed -i "s/-Xms1g/-Xms${MEMORY}m/g" /usr/share/elasticsearch/config/jvm.options && \
    sed -i "s/-Xmx1g/-Xmx${MEMORY}m/g" /usr/share/elasticsearch/config/jvm.options

RUN mkdir /usr/share/elasticsearch/tmp && \
    chown -R 1090:1090 /usr/share/elasticsearch

WORKDIR /usr/share/elasticsearch

RUN ./bin/elasticsearch-users useradd ${USER} -p ${PASSWORD} -r superuser

ENV PATH /usr/share/elasticsearch/bin:$PATH
ENV ES_TMPDIR /usr/share/elasticsearch/tmp

EXPOSE 9202 9302

USER 1090

CMD ["elasticsearch"]
