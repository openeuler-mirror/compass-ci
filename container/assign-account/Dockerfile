# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM debian
MAINTAINER luanshd0525@163.com
ENV DEBIAN_FRONTEND noninteractive

COPY conf/sources.list* /etc/apt/

RUN apt-get update && \
    apt-get install -y ruby-sinatra ruby-json curl && \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo 'Asia/Shanghai' > /etc/timezone
COPY assign-account.rb /usr/local/bin/
COPY get_account_info.rb /usr/local/bin/

CMD ["/usr/local/bin/assign-account.rb"]
