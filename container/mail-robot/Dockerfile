# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM       debian

MAINTAINER Luan Shengde <shdluan@163.com>

ENV        DEBIAN_FRONTEND noninteractive

RUN        apt-get update && \
           apt-get install -y git uuid-runtime ruby-listen ruby-json ruby-mail ruby-rest-client


RUN        echo ':sources: ["http://rubygems.org"]' >> ~/.gemrc && \
           gem install fileutils elasticsearch activesupport
