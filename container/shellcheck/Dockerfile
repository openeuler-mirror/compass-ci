# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM debian

MAINTAINER 18509160991@163.com

ENV DEBIAN_FRONTEND noninteractive

COPY conf/sources.list* /etc/apt/
RUN apt-get update && \
    apt-get install -y shellcheck

VOLUME /shellbox
WORKDIR /shellbox

CMD ["/bin/bash"]
