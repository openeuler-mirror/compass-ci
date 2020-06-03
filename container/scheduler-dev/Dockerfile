FROM alpine:crystal-base

MAINTAINER chief <tongqunfeng@huawei.com>

RUN umask 002 && \
  gem install rest-client && \
  gem install activesupport && \
  gem install git && \
  gem install json && \
  gem install yaml

copy shard.yml /usr/share/crystal/app/shard.yml

WORKDIR /usr/share/crystal/app
RUN shards
RUN sed -i 's:data):data, headers\: HTTP\:\:Headers{"Content-Type" => "application/json"}):' /usr/share/crystal/app/lib/elasticsearch-crystal/src/elasticsearch/api/namespace/common.cr;

CMD ["bash"]

