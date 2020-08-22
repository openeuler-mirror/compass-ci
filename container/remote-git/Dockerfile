# SPDX-License-Identifier: MulanPSL-2.0+

FROM debian

ENV DEBIAN_FRONTEND noninteractive

COPY conf/sources.list* /etc/apt/
RUN apt-get update && \
    apt-get install -y git ruby-json ruby-sinatra

COPY remote-git.rb /usr/local/bin/

CMD ["/usr/local/bin/remote-git.rb"]
