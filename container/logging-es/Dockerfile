# SPDX-License-Identifier: MulanPSL-2.0+

FROM gagara/elasticsearch-oss-arm64:7.6.2

# docker image borrowed from hub.docker.com/r/gagara/elasticsearch-oss-arm64

MAINTAINER Wu Zhende <wuzhende1@huawei.com>

RUN sed -i 's:#network.host\: _site_:network.host\: 0.0.0.0:' /usr/share/elasticsearch/config/elasticsearch.yml;
RUN sed -i '$a path.data: /srv/es/logging-es' /usr/share/elasticsearch/config/elasticsearch.yml;
RUN sed -i '$a node.name: node-1' /usr/share/elasticsearch/config/elasticsearch.yml;
RUN sed -i '$a cluster.initial_master_nodes: ["node-1"]' /usr/share/elasticsearch/config/elasticsearch.yml;

RUN mkdir /usr/share/elasticsearch/tmp && \
    chown -R 1090:1090 /usr/share/elasticsearch

WORKDIR /usr/share/elasticsearch

ENV PATH /usr/share/elasticsearch/bin:$PATH
ENV ES_TMPDIR /usr/share/elasticsearch/tmp

EXPOSE 9202 9302

USER 1090

CMD ["elasticsearch"]
