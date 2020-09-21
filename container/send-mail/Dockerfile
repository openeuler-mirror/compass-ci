# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM debian
MAINTAINER luanshd0525@163.com
ENV DEBIAN_FRONTEND noninteractive

COPY conf/sources.list* /etc/apt/
RUN apt-get update && \
    apt-get install -y ruby-mail ruby-json ruby-sinatra && \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo 'Asia/Shanghai' > /etc/timezone

EXPOSE 25

COPY mail-post.rb /usr/local/bin/
COPY send-mail.rb /usr/local/bin/

CMD ["/usr/local/bin/mail-post.rb"]
