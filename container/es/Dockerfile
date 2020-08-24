# SPDX-License-Identifier: MulanPSL-2.0+

FROM alpine:3.11

RUN sed -i.origin 's|http://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN apk add --no-cache elasticsearch curl

RUN rm -rf /etc/init.d/elasticsearch \
    && rm -rf /usr/share/java/elasticsearch/plugins \
    && mv /usr/share/java/elasticsearch /usr/share/es \
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
    && chown -R 1090:1090 /usr/share/es \
    && chown -R 1090:1090 /srv/es;

RUN sed -i 's:#path.data\: /path/to/data:path.data\: /srv/es:' /usr/share/es/config/elasticsearch.yml;
RUN sed -i 's:#network.host\: _site_:network.host\: 0.0.0.0:' /usr/share/es/config/elasticsearch.yml;
RUN sed -i "s/-Xms256m/-Xms20g/g" /usr/share/es/config/jvm.options
RUN sed -i "s/-Xmx256m/-Xmx20g/g" /usr/share/es/config/jvm.options

WORKDIR /usr/share/es

ENV PATH /usr/share/es/bin:$PATH
ENV ES_TMPDIR /usr/share/es/tmp

VOLUME ["/srv/es"]

EXPOSE 9200 9300

USER 1090
CMD ["elasticsearch"]

