# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

ARG BASE_IMAGE

FROM ${BASE_IMAGE}

ARG USER
ARG PASSWORD

MAINTAINER Wu Zhende <wuzhende666@163.com>

RUN sed -i 's/server.host: "0"/server.host: "0.0.0.0"/' config/kibana.yml && \
    sed -i "6i\elasticsearch.username: ${USER}" config/kibana.yml && \
    sed -i "6i\elasticsearch.password: ${PASSWORD}" config/kibana.yml
