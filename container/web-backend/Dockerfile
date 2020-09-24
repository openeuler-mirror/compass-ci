# SPDX-License-Identifier: MulanPSL-2.0+

FROM debian

MAINTAINER Zhang Yuhang <o0OiIl@hotmail.com>

ENV DEBIAN_FRONTEND noninteractive

COPY conf/sources.list /etc/apt/

RUN apt-get update && \
	apt-get install -y git ruby-json ruby-rails ruby-sinatra && \
	gem sources -r https://rubygems.org/ -a https://gems.ruby-china.com/ && \
	gem install elasticsearch redis git

COPY web-backend /usr/local/bin/

CMD ["/usr/local/bin/web-backend"]
