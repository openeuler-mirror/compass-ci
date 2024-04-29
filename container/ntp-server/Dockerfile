# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM openeuler/openeuler:22.03

MAINTAINER Wang Chenglong <18509160991@163.com>

RUN yum clean all && \
    yum -y update && \
    yum -y install ntp  && \
    yum clean all

RUN ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

COPY ntp.conf /etc/ntp.conf
COPY start-server.sh /

EXPOSE 123

ENTRYPOINT ["/start-server.sh"]
CMD ["sh"]
