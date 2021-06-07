# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM nginx:1.20.0-alpine

MAINTAINER Lu Weitao <luweitaobe@163.com>

ARG KIBANA_GUEST

COPY nginx.conf /etc/nginx/

RUN sed -i "s/KIBANA_GUEST/${KIBANA_GUEST}/" /etc/nginx/nginx.conf
