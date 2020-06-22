FROM alpine:crystal-base

MAINTAINER chief <tongqunfeng@huawei.com>

RUN umask 002 && \
  gem install rest-client activesupport bigdecimal open3 && \
  gem install git json yaml && \
  gem install cucumber

WORKDIR /usr/share/crystal/app
COPY --from=alpine:crystal-shards /usr/share/crystal/app /usr/share/crystal/app

CMD ["bash"]

