# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM fedora:33

RUN groupadd --gid 1090 lkp
RUN useradd --uid 1090 --gid 1090 lkp

RUN yum install -y createrepo ruby ruby-devel make gcc gcc-c++ util-linux bash redhat-rpm-config git cpio diffutils hostname

RUN umask 002 && \
    gem sources -r https://rubygems.org/ -a https://gems.ruby-china.com/ && \
    gem install bunny json activesupport git rest-client io-console elasticsearch:7.11.1 md5sum base64 clockwork

COPY submit_arg.yaml /etc/
COPY secrets_info.yaml /etc/
