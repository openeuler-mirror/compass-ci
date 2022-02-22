# SPDX-License-Identifier: MulanPSL-2.0+

FROM debian:buster

MAINTAINER Lu Weitao <luweitaobe@163.com>

ENV DEBIAN_FRONTEND noninteractive

COPY conf/sources.list /etc/apt/

RUN apt-get update && \
	apt-get install -y git ruby-json ruby-rails ruby-sinatra && \
	gem sources -r https://rubygems.org/ -a https://gems.ruby-china.com/ && \
	gem install elasticsearch:7.11.1 redis git terminal-table

COPY data-api /usr/local/bin/

CMD ["/usr/local/bin/data-api"]
