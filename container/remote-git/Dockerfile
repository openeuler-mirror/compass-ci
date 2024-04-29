# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM debian:bookworm

ENV DEBIAN_FRONTEND noninteractive

COPY conf/sources.list* /etc/apt/
RUN apt-get clean && \
    apt-get update && \
    apt-get install -y git ruby-json ruby-sinatra

RUN groupadd -g 1999 committer && useradd -m -u 1090 -g 1999 lkp

COPY remote-git.rb /usr/local/bin/

RUN apt-get remove -y gcc cpp gdb

CMD ["/usr/local/bin/remote-git.rb"]
