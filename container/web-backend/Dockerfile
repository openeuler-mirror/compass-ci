# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM centos:7

RUN yum -y install gcc make tar gzip openssl-devel gcc-c++ zlib createrepo iproute wget

# download the source file may take a long time, can prepare download it and use
# the following line instead of command wget
#   COPY ruby-2.7.6.tar.gz /
RUN wget https://ftp.ruby-lang.org/pub/ruby/2.7/ruby-2.7.6.tar.gz -P /

RUN cd / && tar xzvf ruby-2.7.6.tar.gz && cd ruby-2.7.6 && ./configure && make && make install

RUN gem install zlib activesupport:6.1.4.4 rest-client grpc:1.17 && \
    gem install etcdv3 xml-simple elasticsearch:7.11.1 logger json-schema redis git terminal-table && \
    gem install sinatra
