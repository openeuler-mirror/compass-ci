# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.


FROM logging-es-base:latest
MAINTAINER Wu Zhende <wuzhende666@163.com>

ARG USER
ARG PASSWORD
ARG MEMORY

WORKDIR /usr/share/elasticsearch

RUN ./bin/elasticsearch-users useradd ${USER} -p ${PASSWORD} -r superuser
RUN echo "-Xms${MEMORY}m" >> /usr/share/elasticsearch/config/jvm.options && \
    echo "-Xmx${MEMORY}m" >> /usr/share/elasticsearch/config/jvm.options


ENV PATH /usr/share/elasticsearch/bin:$PATH
ENV ES_TMPDIR /usr/share/elasticsearch/tmp

EXPOSE 9202 9302

USER es

CMD ["sh", "-c", "mkdir -p /tmp/logging-es/config && cp -rf /usr/share/elasticsearch/config/* /tmp/logging-es/config/ && elasticsearch"]
