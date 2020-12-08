# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

ARG BASE_IMAGE

FROM ${BASE_IMAGE}

# docker image borrowed from hub.docker.com/r/gagara/kibana-oss-arm64

MAINTAINER Wu Zhende <wuzhende666@163.com>

RUN sed -i 's/server.host: "0"/server.host: "0.0.0.0"/' config/kibana.yml

USER root
RUN yum -y install wget \
    && wget https://github.com/sivasamyk/logtrail/releases/download/v0.1.31/logtrail-7.6.2-0.1.31.zip -O /logtrail-7.6.2-0.1.31.zip

USER 1090
RUN ./bin/kibana-plugin install file:///logtrail-7.6.2-0.1.31.zip \
    && rm -rf /tmp/logtrail-7.6.2-0.1.31.zip

COPY --chown=1090:1090 logtrail.json /usr/share/kibana/plugins/logtrail/logtrail.json
