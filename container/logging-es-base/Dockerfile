# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM openeuler/openeuler:22.03
MAINTAINER Wu Zhende <wuzhende666@163.com>

ARG ARCH

RUN yum clean all && \
    yum -y update && \
    yum -y install tar gzip shadow 

RUN groupadd -r -g 1090 es && useradd -r -u 1090 -g es es

RUN curl -o elasticsearch-7.11.1-linux-x86_64.tar.gz https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-7.11.1-linux-${ARCH}.tar.gz && \
    tar -xzvf elasticsearch-7.11.1-linux-x86_64.tar.gz -C /usr/share && \
    rm -f elasticsearch-7.11.1-linux-x86_64.tar.gz && \
    mv /usr/share/elasticsearch-7.11.1 /usr/share/elasticsearch && \
    chmod -R a+xr /usr/share/elasticsearch/ && \
    rm /usr/share/elasticsearch/bin/elasticsearch-sql-cli && \
    rm /usr/share/elasticsearch/bin/elasticsearch-sql-cli-7.11.1.jar && \
    rm /usr/share/elasticsearch/modules/x-pack-core/log4j-1.2-api-2.11.1.jar && \
    rm /usr/share/elasticsearch/modules/x-pack-identity-provider/log4j-slf4j-impl-2.11.1.jar && \
    rm /usr/share/elasticsearch/modules/x-pack-security/log4j-slf4j-impl-2.11.1.jar && \
    rm /usr/share/elasticsearch/lib/log4j-api-2.11.1.jar && \
    rm /usr/share/elasticsearch/lib/log4j-core-2.11.1.jar && \
    curl https://repo1.maven.org/maven2/org/apache/logging/log4j/log4j-1.2-api/2.20.0/log4j-1.2-api-2.20.0.jar -o /usr/share/elasticsearch/modules/x-pack-core/log4j-1.2-api-2.20.0.jar && \
    curl https://repo1.maven.org/maven2/org/apache/logging/log4j/log4j-slf4j-impl/2.20.0/log4j-slf4j-impl-2.20.0.jar -o /usr/share/elasticsearch/modules/x-pack-identity-provider/log4j-slf4j-impl-2.20.0.jar && \
    cp /usr/share/elasticsearch/modules/x-pack-identity-provider/log4j-slf4j-impl-2.20.0.jar /usr/share/elasticsearch/modules/x-pack-security/ && \
    curl https://repo1.maven.org/maven2/org/apache/logging/log4j/log4j-api/2.20.0/log4j-api-2.20.0.jar -o /usr/share/elasticsearch/lib/log4j-api-2.20.0.jar && \
    curl https://repo1.maven.org/maven2/org/apache/logging/log4j/log4j-core/2.20.0/log4j-core-2.20.0.jar -o /usr/share/elasticsearch/lib/log4j-core-2.20.0.jar && \
    rm -f /usr/share/elasticsearch/modules/ingest-geoip/jackson-annotations-2.10.4.jar && \
    rm -f /usr/share/elasticsearch/modules/ingest-geoip/jackson-databind-2.10.4.jar && \
    rm -f /usr/share/elasticsearch/lib/jackson-core-2.10.4.jar && \
    rm -f /usr/share/elasticsearch/lib/jackson-dataformat-yaml-2.10.4.jar && \
    rm -f /usr/share/elasticsearch/lib/jackson-dataformat-smile-2.10.4.jar && \
    rm -f /usr/share/elasticsearch/lib/jackson-dataformat-cbor-2.10.4.jar && \
    curl https://repo1.maven.org/maven2/com/fasterxml/jackson/core/jackson-annotations/2.15.2/jackson-annotations-2.15.2.jar  -o /usr/share/elasticsearch/modules/ingest-geoip/jackson-annotations-2.15.2.jar && \
    curl https://repo1.maven.org/maven2/com/fasterxml/jackson/core/jackson-core/2.15.2/jackson-core-2.15.2.jar  -o /usr/share/elasticsearch/lib/jackson-core-2.15.2.jar && \
    curl https://repo1.maven.org/maven2/com/fasterxml/jackson/core/jackson-databind/2.15.2/jackson-databind-2.15.2.jar  -o /usr/share/elasticsearch/modules/ingest-geoip/jackson-databind-2.15.2.jar && \
    curl https://repo1.maven.org/maven2/com/fasterxml/jackson/dataformat/jackson-dataformat-yaml/2.15.2/jackson-dataformat-yaml-2.15.2.jar  -o /usr/share/elasticsearch/lib/jackson-dataformat-yaml-2.15.2.jar && \
    curl https://repo1.maven.org/maven2/com/fasterxml/jackson/dataformat/jackson-dataformat-smile/2.15.2/jackson-dataformat-smile-2.15.2.jar  -o /usr/share/elasticsearch/lib/jackson-dataformat-smile-2.15.2.jar && \
    curl https://repo1.maven.org/maven2/com/fasterxml/jackson/dataformat/jackson-dataformat-cbor/2.15.2/jackson-dataformat-cbor-2.15.2.jar  -o /usr/share/elasticsearch/lib/jackson-dataformat-cbor-2.15.2.jar && \
    rm -f /usr/share/elasticsearch/modules/x-pack-core/netty-buffer-4.1.49.Final.jar && \
    rm -f /usr/share/elasticsearch/modules/x-pack-core/netty-common-4.1.49.Final.jar && \
    rm -f /usr/share/elasticsearch/modules/x-pack-core/netty-resolver-4.1.49.Final.jar && \
    rm -f /usr/share/elasticsearch/modules/x-pack-core/netty-handler-4.1.49.Final.jar && \
    rm -f /usr/share/elasticsearch/modules/x-pack-core/netty-transport-4.1.49.Final.jar && \
    rm -f /usr/share/elasticsearch/modules/x-pack-core/netty-codec-4.1.49.Final.jar && \
    rm -f /usr/share/elasticsearch/modules/x-pack-core/netty-codec-http-4.1.49.Final.jar && \
    rm -f /usr/share/elasticsearch/modules/transport-netty4/netty-buffer-4.1.49.Final.jar && \
    rm -f /usr/share/elasticsearch/modules/transport-netty4/netty-common-4.1.49.Final.jar && \
    rm -f /usr/share/elasticsearch/modules/transport-netty4/netty-resolver-4.1.49.Final.jar && \
    rm -f /usr/share/elasticsearch/modules/transport-netty4/netty-handler-4.1.49.Final.jar && \
    rm -f /usr/share/elasticsearch/modules/transport-netty4/netty-transport-4.1.49.Final.jar && \
    rm -f /usr/share/elasticsearch/modules/transport-netty4/netty-codec-4.1.49.Final.jar && \
    rm -f /usr/share/elasticsearch/modules/transport-netty4/netty-codec-http-4.1.49.Final.jar && \
    curl https://repo1.maven.org/maven2/io/netty/netty-buffer/4.1.94.Final/netty-buffer-4.1.94.Final.jar -o /usr/share/elasticsearch/modules/x-pack-core/netty-buffer-4.1.94.Final.jar  && \
    curl https://repo1.maven.org/maven2/io/netty/netty-buffer/4.1.94.Final/netty-buffer-4.1.94.Final.jar -o /usr/share/elasticsearch/modules/transport-netty4/netty-buffer-4.1.94.Final.jar  && \
    curl https://repo1.maven.org/maven2/io/netty/netty-common/4.1.94.Final/netty-common-4.1.94.Final.jar -o /usr/share/elasticsearch/modules/x-pack-core/netty-common-4.1.94.Final.jar && \
    curl https://repo1.maven.org/maven2/io/netty/netty-common/4.1.94.Final/netty-common-4.1.94.Final.jar -o /usr/share/elasticsearch/modules/transport-netty4/netty-common-4.1.94.Final.jar && \
    curl https://repo1.maven.org/maven2/io/netty/netty-resolver/4.1.94.Final/netty-resolver-4.1.94.Final.jar -o /usr/share/elasticsearch/modules/x-pack-core/netty-resolver-4.1.94.Final.jar  && \
    curl https://repo1.maven.org/maven2/io/netty/netty-resolver/4.1.94.Final/netty-resolver-4.1.94.Final.jar -o /usr/share/elasticsearch/modules/transport-netty4/netty-resolver-4.1.94.Final.jar  && \
    curl https://repo1.maven.org/maven2/io/netty/netty-handler/4.1.94.Final/netty-handler-4.1.94.Final.jar -o /usr/share/elasticsearch/modules/x-pack-core/netty-handler-4.1.94.Final.jar  && \
    curl https://repo1.maven.org/maven2/io/netty/netty-handler/4.1.94.Final/netty-handler-4.1.94.Final.jar -o /usr/share/elasticsearch/modules/transport-netty4/netty-handler-4.1.94.Final.jar  && \
    curl https://repo1.maven.org/maven2/io/netty/netty-transport/4.1.94.Final/netty-transport-4.1.94.Final.jar -o /usr/share/elasticsearch/modules/x-pack-core/netty-transport-4.1.94.Final.jar && \
    curl https://repo1.maven.org/maven2/io/netty/netty-transport/4.1.94.Final/netty-transport-4.1.94.Final.jar -o /usr/share/elasticsearch/modules/transport-netty4/netty-transport-4.1.94.Final.jar && \
    curl https://repo1.maven.org/maven2/io/netty/netty-codec/4.1.94.Final/netty-codec-4.1.94.Final.jar -o /usr/share/elasticsearch/modules/x-pack-core/netty-codec-4.1.94.Final.jar && \
    curl https://repo1.maven.org/maven2/io/netty/netty-codec/4.1.94.Final/netty-codec-4.1.94.Final.jar -o /usr/share/elasticsearch/modules/transport-netty4/netty-codec-4.1.94.Final.jar && \
    curl https://repo1.maven.org/maven2/io/netty/netty-codec-http/4.1.94.Final/netty-codec-http-4.1.94.Final.jar -o /usr/share/elasticsearch/modules/x-pack-core/netty-codec-http-4.1.94.Final.jar && \
    curl https://repo1.maven.org/maven2/io/netty/netty-codec-http/4.1.94.Final/netty-codec-http-4.1.94.Final.jar -o /usr/share/elasticsearch/modules/transport-netty4/netty-codec-http-4.1.94.Final.jar && \
    rm -f /usr/share/elasticsearch/modules/x-pack-core/httpclient-4.5.10.jar && \
    rm -f /usr/share/elasticsearch/modules/reindex/httpclient-4.5.10.jar && \
    rm -f /usr/share/elasticsearch/modules/x-pack-identity-provider/httpclient-cache-4.5.10.jar && \
    rm -f /usr/share/elasticsearch/modules/kibana/httpclient-4.5.10.jar && \
    rm -f /usr/share/elasticsearch/modules/x-pack-fleet/httpclient-4.5.10.jar && \
    rm -f /usr/share/elasticsearch/modules/x-pack-security/httpclient-cache-4.5.10.jar && \
    curl https://repo1.maven.org/maven2/org/apache/httpcomponents/httpclient/4.5.14/httpclient-4.5.14.jar -o /httpclient-4.5.14.jar && \
    curl https://repo1.maven.org/maven2/org/apache/httpcomponents/httpclient-cache/4.5.14/httpclient-cache-4.5.14.jar -o /httpclient-cache-4.5.14.jar && \
    cp /httpclient-4.5.14.jar /usr/share/elasticsearch/modules/x-pack-core/ && \
    cp /httpclient-4.5.14.jar /usr/share/elasticsearch/modules/reindex/ && \
    cp /httpclient-4.5.14.jar /usr/share/elasticsearch/modules/kibana/ && \
    cp /httpclient-4.5.14.jar /usr/share/elasticsearch/modules/x-pack-fleet/ && \
    cp /httpclient-cache-4.5.14.jar /usr/share/elasticsearch/modules/x-pack-identity-provider/ && \
    cp /httpclient-cache-4.5.14.jar /usr/share/elasticsearch/modules/x-pack-security/ && \
    rm -f /httpclient-4.5.14.jar && \
    rm -f /httpclient-cache-4.5.14.jar && \
    rm -f /usr/share/elasticsearch/lib/snakeyaml-1.26.jar && \
    curl https://repo1.maven.org/maven2/org/yaml/snakeyaml/2.0/snakeyaml-2.0.jar -o /usr/share/elasticsearch/lib/snakeyaml-2.0.jar && \
    rm -f /usr/share/elasticsearch/modules/x-pack-identity-provider/xmlsec-2.1.4.jar && \
    rm -f /usr/share/elasticsearch/modules/x-pack-security/xmlsec-2.1.4.jar && \
    curl https://repo1.maven.org/maven2/org/apache/santuario/xmlsec/2.1.8/xmlsec-2.1.8.jar -o /usr/share/elasticsearch/modules/x-pack-identity-provider/xmlsec-2.1.8.jar && \
    cp /usr/share/elasticsearch/modules/x-pack-identity-provider/xmlsec-2.1.8.jar /usr/share/elasticsearch/modules/x-pack-security/ && \
    rm -f /usr/share/elasticsearch/modules/x-pack-identity-provider/guava-19.0.jar && \
    rm -f /usr/share/elasticsearch/modules/x-pack-watcher/guava-27.1-jre.jar && \
    rm -f /usr/share/elasticsearch/modules/x-pack-security/guava-19.0.jar && \
    curl https://repo1.maven.org/maven2/com/google/guava/guava/32.1.1-jre/guava-32.1.1-jre.jar -o /usr/share/elasticsearch/modules/x-pack-identity-provider/guava-32.1.1-jre.jar && \
    cp /usr/share/elasticsearch/modules/x-pack-identity-provider/guava-32.1.1-jre.jar /usr/share/elasticsearch/modules/x-pack-watcher/ && \
    cp /usr/share/elasticsearch/modules/x-pack-identity-provider/guava-32.1.1-jre.jar /usr/share/elasticsearch/modules/x-pack-security/

RUN mkdir /usr/share/elasticsearch/tmp && \
    chown -R es:es /usr/share/elasticsearch

COPY elasticsearch.yml /usr/share/elasticsearch/config/

WORKDIR /usr/share/elasticsearch

ENV PATH /usr/share/elasticsearch/bin:$PATH
ENV ES_TMPDIR /usr/share/elasticsearch/tmp

