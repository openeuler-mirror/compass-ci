# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM debian

MAINTAINER Cao Xueliang <caoxl78320@163.com>

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && \
    apt-get install -y ruby-json ruby-sinatra curl

COPY routes.rb /usr/local/bin/
COPY views /usr/local/bin/views/

CMD ["/usr/local/bin/routes.rb"]
