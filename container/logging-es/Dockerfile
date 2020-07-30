FROM gagara/elasticsearch-oss-arm64:7.6.2

# docker image borrowed from hub.docker.com/r/gagara/elasticsearch-oss-arm64

MAINTAINER Wu Zhende <wuzhende1@huawei.com>

RUN rm -rf /etc/init.d/elasticsearch \
    && rm -rf /usr/share/java/elasticsearch/plugins \
    && mv /usr/share/elasticsearch /usr/share/es \
    && adduser -D -h /usr/share/es elasticsearch \
    && echo "===> Creating Elasticsearch Paths..." \
    && for path in \
         /srv/es \
         /usr/share/es/logs \
         /usr/share/es/config \
         /usr/share/es/config/scripts \
         /usr/share/es/tmp \
         /usr/share/es/plugins \
       ; do \
         mkdir -p "$path"; \
       done \
    && chown -R elasticsearch:elasticsearch /usr/share/es \
    && chown -R elasticsearch:elasticsearch /srv/es;

RUN sed -i 's:#network.host\: _site_:network.host\: 0.0.0.0:' /usr/share/es/config/elasticsearch.yml;
RUN sed -i '$a path.data: /srv/es' /usr/share/es/config/elasticsearch.yml;
RUN sed -i '$a node.name: node-1' /usr/share/es/config/elasticsearch.yml;
RUN sed -i '$a cluster.initial_master_nodes: ["node-1"]' /usr/share/es/config/elasticsearch.yml;

WORKDIR /usr/share/es

ENV PATH /usr/share/es/bin:$PATH
ENV ES_TMPDIR /usr/share/es/tmp

VOLUME ["/srv/logging-es"]

EXPOSE 9202 9302

USER elasticsearch
CMD ["elasticsearch"]
