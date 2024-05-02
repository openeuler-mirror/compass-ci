# SPDX-License-Identifier: MulanPSL-2.0+

FROM debian:bookworm

ENV DEBIAN_FRONTEND noninteractive

COPY conf/sources.list /etc/apt/
RUN rm /etc/apt/sources.list.d/*

RUN apt-get update && \
	apt-get install -y git uuid-runtime ruby-json ruby-rails ruby-sinatra ruby-jwt ruby-rest-client curl && \
	gem install public_suffix -v 4.0.7 && \
	gem sources -r https://rubygems.org/ -a https://gems.ruby-china.com/ && \
	gem install elasticsearch:7.11.1 redis git terminal-table

RUN groupadd -g 1090 lkp && useradd -m -u 1090 -g 1090 lkp

RUN apt-get remove gcc gdb cpp -y
