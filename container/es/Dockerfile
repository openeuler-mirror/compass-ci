# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM elasticsearch:7.11.1@sha256:d52cda1e73d1b1915ba2d76ca1e426620c7b5d6942d9d2f432259503974ba786

ARG MEMORY

RUN sed -i 's:#network.host\: _site_:network.host\: 0.0.0.0:' /usr/share/elasticsearch/config/elasticsearch.yml && \
    sed -i '$a path.data: /srv/es' /usr/share/elasticsearch/config/elasticsearch.yml && \
    sed -i '$a node.name: node-1' /usr/share/elasticsearch/config/elasticsearch.yml && \
    sed -i '$a cluster.initial_master_nodes: ["node-1"]' /usr/share/elasticsearch/config/elasticsearch.yml && \
    sed -i "s/-Xms256m/-Xms${MEMORY}m/g" /usr/share/elasticsearch/config/jvm.options && \
    sed -i "s/-Xmx256m/-Xmx${MEMORY}m/g" /usr/share/elasticsearch/config/jvm.options

RUN mkdir /usr/share/elasticsearch/tmp && \
    chown -R 1090:1090 /usr/share/elasticsearch

WORKDIR /usr/share/elasticsearch

ENV PATH /usr/share/elasticsearch/bin:$PATH
ENV ES_TMPDIR /usr/share/elasticsearch/tmp

VOLUME ["/srv/es"]

EXPOSE 9200 9300

USER 1090
CMD ["elasticsearch"]
