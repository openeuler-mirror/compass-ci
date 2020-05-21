FROM alpine:3.11

RUN apk add --no-cache elasticsearch

RUN rm -rf /etc/init.d/elasticsearch \
    && rm -rf /usr/share/java/elasticsearch/plugins \
    && mv /usr/share/java/elasticsearch /usr/share/es \
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
    && cp /etc/elasticsearch/*.* /usr/share/es/config \
    && chown -R elasticsearch:elasticsearch /usr/share/es \
    && chown -R elasticsearch:elasticsearch /srv/es;

RUN sed -i 's:#path.data\: /path/to/data:path.data\: /srv/es:' /usr/share/es/config/elasticsearch.yml; 
RUN sed -i 's:#network.host\: _site_:network.host\: 0.0.0.0:' /usr/share/es/config/elasticsearch.yml; 

WORKDIR /usr/share/es

ENV PATH /usr/share/es/bin:$PATH
ENV ES_TMPDIR /usr/share/es/tmp

VOLUME ["/srv/es"]

EXPOSE 9200 9300

USER elasticsearch
CMD ["elasticsearch"]

