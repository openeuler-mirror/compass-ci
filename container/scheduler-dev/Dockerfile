# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM alpine:crystal-base

MAINTAINER chief <taxcom@tom.com>

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN umask 002 && \
  echo ':sources: ["http://rubygems.org"]' >> ~/.gemrc && \
  gem install rest-client activesupport bigdecimal open3 && \
  gem install git json yaml && \
  gem install cucumber

WORKDIR /usr/share/crystal/app
COPY --from=alpine:crystal-shards /usr/share/crystal/app /usr/share/crystal/app

CMD ["bash"]

