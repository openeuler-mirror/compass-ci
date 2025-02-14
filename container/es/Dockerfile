# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM es-base:latest

ARG USER
ARG PASSWORD
ARG MEMORY

RUN echo "-Xms${MEMORY}m" >> /usr/share/elasticsearch/config/jvm.options && \
    echo "-Xmx${MEMORY}m" >> /usr/share/elasticsearch/config/jvm.options

RUN /usr/share/elasticsearch/bin/elasticsearch-users useradd ${USER} -p ${PASSWORD} -r superuser

WORKDIR /usr/share/elasticsearch

ENV PATH /usr/share/elasticsearch/bin:$PATH
ENV JAVA_HOME /usr/share/elasticsearch/jdk
ENV ES_TMPDIR /usr/share/elasticsearch/tmp

VOLUME ["/srv/es"]

EXPOSE 9200 9300

USER 1090
CMD ["sh", "-c", "mkdir -p /tmp/es/config && cp -rf /usr/share/elasticsearch/config/* /tmp/es/config/ && elasticsearch"]
