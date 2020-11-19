# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM centos:7

MAINTAINER Yu Chuan <13186087857@163.com>, Shi Zhichao <angus_robot@163.com>

RUN rpm --import /etc/pki/rpm-gpg/RPM*

RUN rm -rf /etc/yum.repos.d/*
COPY root /
RUN yum makecache && \
    yum install -y --skip-broken libvirt libguestfs-tools xz expect openssl && \
    yum clean all

ENV EXTRACT_USER=extract
ENV EXTRACT_ROOT=/root/extract

RUN useradd $EXTRACT_USER && \
    usermod -aG kvm,qemu,root $EXTRACT_USER
