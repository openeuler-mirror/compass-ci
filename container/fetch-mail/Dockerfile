# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM centos:8
MAINTAINER Luan Shengde <shdluan@163.com>
ENV DEBIAN_FRONTEND noninteractive

RUN groupadd -g 1147 mailer
RUN useradd -u 1144 -g 1147 mailer 
RUN mkdir /etc/yum.repos.d.backup && \
    mv /etc/yum.repos.d/*.repo /etc/yum.repos.d.backup && \
    curl https://mirrors.aliyun.com/repo/Centos-vault-8.5.2111.repo > /etc/yum.repos.d/CentOS-Base.repo && \
    yum makecache && \
    yum install -y procmail fetchmail

COPY fetchmailrc.template /home/mailer/.fetchmailrc
COPY procmailrc.template /home/mailer/.procmailrc
COPY run.sh /home/mailer/

RUN chmod 600 /home/mailer/.fetchmailrc
RUN chmod 600 /home/mailer/.procmailrc
RUN chown -R mailer:mailer /home/mailer
RUN chmod +x /home/mailer/run.sh
