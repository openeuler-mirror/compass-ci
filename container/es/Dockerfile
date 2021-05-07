# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG MEMORY
ARG USER
ARG PASSWORD

RUN sed -i 's:#network.host\: _site_:network.host\: 0.0.0.0:' /usr/share/elasticsearch/config/elasticsearch.yml && \
    sed -i '$a path.data: /srv/es' /usr/share/elasticsearch/config/elasticsearch.yml && \
    sed -i '$a node.name: node-1' /usr/share/elasticsearch/config/elasticsearch.yml && \
    sed -i '$a cluster.initial_master_nodes: ["node-1"]' /usr/share/elasticsearch/config/elasticsearch.yml && \
    sed -i '$a xpack.security.enabled: true' /usr/share/elasticsearch/config/elasticsearch.yml && \
    sed -i '$a xpack.license.self_generated.type: basic' /usr/share/elasticsearch/config/elasticsearch.yml && \
    sed -i '$a xpack.security.transport.ssl.enabled: true' /usr/share/elasticsearch/config/elasticsearch.yml && \
    echo "-Xms${MEMORY}m" >> /usr/share/elasticsearch/config/jvm.options && \
    echo "-Xmx${MEMORY}m" >> /usr/share/elasticsearch/config/jvm.options

RUN mkdir /usr/share/elasticsearch/tmp && \
    chown -R 1090:1090 /usr/share/elasticsearch

WORKDIR /usr/share/elasticsearch

RUN ./bin/elasticsearch-users useradd ${USER} -p ${PASSWORD} -r superuser

ENV PATH /usr/share/elasticsearch/bin:$PATH
ENV ES_TMPDIR /usr/share/elasticsearch/tmp

VOLUME ["/srv/es"]

EXPOSE 9200 9300

USER 1090
CMD ["elasticsearch"]
