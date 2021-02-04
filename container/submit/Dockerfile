# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM debian

MAINTAINER Luan Shengde <shdluan@163.com>

ENV DEBIAN_FRONTEND noninteractive

# it may take a long time, even break up if you use default source address to install pkgs.
# you can delete the following step if you do not want to use it.
COPY conf/sources.list /etc/apt/

RUN apt-get update && \
    apt-get install -y git ruby ruby-dev make libssl-dev gcc g++ sudo uuid-runtime

# it may take a long time, even break up if you use default source address for the gem.
# delete the following step if you do not want to use the default one.
RUN gem sources -r https://rubygems.org/ -a https://gems.ruby-china.com/

RUN gem install git faye-websocket activesupport rest-client

WORKDIR /srv

RUN git clone https://gitee.com/wu_fengguang/lkp-tests.git
RUN cd lkp-tests && make install
