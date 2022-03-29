# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM centos:8

MAINTAINER Xu Xijian <hdxuxijian@163.com>

RUN mkdir /etc/yum.repos.d.backup && \
    mv /etc/yum.repos.d/*.repo /etc/yum.repos.d.backup && \
    curl https://mirrors.aliyun.com/repo/Centos-vault-8.5.2111.repo > /etc/yum.repos.d/CentOS-Base.repo && \
    yum makecache && \
    yum install -y rsync
