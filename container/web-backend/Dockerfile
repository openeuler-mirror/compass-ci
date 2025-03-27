# SPDX-License-Identifier: MulanPSL-2.0+

FROM debian:bookworm

ARG PROJECT_NAME

MAINTAINER Lu Weitao <luweitaobe@163.com>

ENV DEBIAN_FRONTEND noninteractive

COPY conf/sources.list /etc/apt/
RUN rm /etc/apt/sources.list.d/*

RUN apt-get clean && \
	apt-get update && \
	apt-get install -y git uuid-runtime ruby-json ruby-rails ruby-sinatra ruby-jwt ruby-rest-client curl && \
	gem install public_suffix -v 4.0.7 && \
	gem sources -r https://rubygems.org/ -a https://gems.ruby-china.com/ && \
	gem install google-protobuf:3.25.0 elasticsearch:7.11.1 redis git terminal-table etcdv3:0.11.6 

COPY ${PROJECT_NAME} /c/${PROJECT_NAME}
COPY lkp-tests /c/lkp-tests

RUN groupadd -g 1090 lkp && useradd -m -u 1090 -g 1090 lkp

RUN chown -R lkp:lkp /c/${PROJECT_NAME} /c/lkp-tests && chmod -R 750 /c/${PROJECT_NAME} /c/lkp-tests

RUN apt-get remove gcc gdb cpp -y
WORKDIR /c/${PROJECT_NAME}/container/web-backend/
