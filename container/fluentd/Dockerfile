# SPDX-License-Identifier: MulanPSL-2.0+

FROM alpine:3.11

MAINTAINER Wu Zhende <wuzhende1@huawei.com>

RUN sed -i.origin 's|http://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN apk update

RUN apk add --no-cache 'ruby-dev' \
    'g++' 'gcc' 'pcre' 'libevent' 'make' 'git' 'cpio' 'bash'

RUN umask 002 &&\
    gem install fluentd &&\
    gem install fluent-plugin-rabbitmq &&\
    gem install fluent-plugin-elasticsearch &&\
    gem install fluent-plugin-tail-ex &&\
    gem install fluent-plugin-tail-multiline &&\
    gem install json &&\
    gem install async &&\
    gem install webrick &&\
    gem install io-console &&\
    gem install etc

COPY --chown=1090:1090 docker-fluentd.conf /fluentd/etc/docker-fluentd.conf

EXPOSE 24224 24224/udp
