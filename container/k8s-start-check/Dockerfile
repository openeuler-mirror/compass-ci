# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM openeuler/openeuler:22.03

ARG PROJECT_NAME

MAINTAINER He Shoucheng <15695901908@163.com>

COPY openEuler.repo /etc/yum.repos.d/

RUN yum clean all && \
	yum update -y && \
	yum install -y ca-certificates python3-3.9.9 shadow && \
	yum install -y git util-linux python3-pip

ENV PIP_SOURCE https://mirrors.huaweicloud.com/repository/pypi/simple/

RUN groupadd -g 1999 committer && useradd -m -u 1090 -g 1999 lkp

COPY requirements.txt .

RUN umask 002 && pip3 install -r ./requirements.txt -i ${PIP_SOURCE}

COPY --chown=1090 ${PROJECT_NAME} /opt/${PROJECT_NAME}

WORKDIR /opt/${PROJECT_NAME}/src/libpy
