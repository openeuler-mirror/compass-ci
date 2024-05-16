# SPDX-License-Identifier: MulanPSL-2.0+

FROM debian:bookworm

MAINTAINER Lu Weitao <luweitaobe@163.com>

ENV DEBIAN_FRONTEND noninteractive

COPY conf/sources.list /etc/apt/
RUN rm /etc/apt/sources.list.d/*

RUN apt-get clean && \
    apt-get update && \
    apt-get -y upgrade && \
    apt-get install -y git ruby-json ruby-rails ruby-sinatra

RUN gem sources -r https://rubygems.org/ -a https://gems.ruby-china.com/ && \
    gem install public_suffix -v 4.0.7 && \
    gem install elasticsearch:7.11.1 redis git terminal-table

COPY data-api /usr/local/bin/

RUN groupadd -g 1090 lkp && useradd -m -u 1090 -g 1090 lkp

COPY cbs /c/compass-ci
COPY lkp-tests /c/lkp-tests

RUN chown -R lkp:lkp /c/compass-ci /c/lkp-tests && chown -R 750 /c/compass-ci /c/lkp-tests

RUN apt-get remove gdb gcc cpp -y

CMD ["/usr/local/bin/data-api"]
