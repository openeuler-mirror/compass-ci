# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM debian:buster
MAINTAINER Luan Shengde <shdluan@163.com>
ENV DEBIAN_FRONTEND noninteractive

COPY conf/sources.list* /etc/apt/

RUN apt-get update && \
    apt-get install -y ruby-mail ruby-json ruby-sinatra ruby-redis ruby-rufus-scheduler
