# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM kibana-base:latest

ARG USER
ARG PASSWORD

MAINTAINER Wu Zhende <wuzhende666@163.com>

WORKDIR /usr/share/kibana

RUN sed -i '/^elasticsearch.username/c \elasticsearch.username: '"${USER}"'' config/kibana.yml
RUN sed -i '/^elasticsearch.password/c \elasticsearch.password: '"${PASSWORD}"'' config/kibana.yml
RUN sed -i '6i\i18n.locale: "zh-CN"' config/kibana.yml

EXPOSE 5601
CMD ["bin/kibana", "--allow-root"]
