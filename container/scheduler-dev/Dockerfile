# SPDX-License-Identifier: MulanPSL-2.0+

FROM alpine:crystal-base

MAINTAINER chief <tongqunfeng@huawei.com>

RUN sed -i.origin 's|http://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN umask 002 && \
  gem install rest-client activesupport bigdecimal open3 && \
  gem install git json yaml && \
  gem install cucumber

WORKDIR /usr/share/crystal/app
COPY --from=alpine:crystal-shards /usr/share/crystal/app /usr/share/crystal/app

CMD ["bash"]

