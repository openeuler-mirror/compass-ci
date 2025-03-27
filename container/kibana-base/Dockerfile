# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM openeuler/openeuler:22.03

ARG ARCH

MAINTAINER Wu Zhende <wuzhende666@163.com>

RUN yum clean all && \
    yum -y update && \
    yum -y install tar gzip java-11-openjdk findutils

RUN curl https://artifacts.elastic.co/downloads/kibana/kibana-7.11.1-linux-${ARCH}.tar.gz -o kibana-7.11.1-linux-${ARCH}.tar.gz && \
    tar -xzvf kibana-7.11.1-linux-${ARCH}.tar.gz -C /usr/share/ && \
    rm -f kibana-7.11.1-linux-${ARCH}.tar.gz && \
    mv /usr/share/kibana-7.11.1-linux-${ARCH} /usr/share/kibana && \
    chmod -R a+rx /usr/share/kibana

COPY kibana.yml /usr/share/kibana/config/
WORKDIR /usr/share/kibana

RUN sed -i 's/server.host: "0"/server.host: "0.0.0.0"/' config/kibana.yml
