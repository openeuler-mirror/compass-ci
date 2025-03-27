# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM kibana-base:latest

MAINTAINER Wu Zhende <wuzhende666@163.com>

ARG USER
ARG PASSWORD

WORKDIR /usr/share/kibana

RUN sed -i '/^elasticsearch.username/c \elasticsearch.username: '"${USER}"'' config/kibana.yml && \
    sed -i '/^elasticsearch.password/c \elasticsearch.password: '"${PASSWORD}"'' config/kibana.yml &&\
    sed -i '6i\i18n.locale: "zh-CN"' config/kibana.yml && \
    sed -i '6ixpack.reporting.enabled: true' config/kibana.yml


EXPOSE 5601
CMD ["bin/kibana", "--allow-root"]
