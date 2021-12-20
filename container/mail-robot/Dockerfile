# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM       debian:buster

MAINTAINER Luan Shengde <shdluan@163.com>

ENV        DEBIAN_FRONTEND noninteractive

COPY conf/sources.list* /etc/apt/

RUN        apt-get update && \
           apt-get install -y git uuid-runtime ruby-listen ruby-json ruby-mail ruby-rest-client ruby-git


RUN        gem sources -r https://rubygems.org/ -a https://gems.ruby-china.com/ && \
           gem install fileutils elasticsearch activesupport:6.1.4.4
