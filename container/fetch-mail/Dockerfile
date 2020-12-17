# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM centos:latest
MAINTAINER Luan Shengde <shdluan@163.com>
ENV DEBIAN_FRONTEND noninteractive

RUN useradd -u 1144 -g 1147 mailer 
RUN yum update -y
RUN yum install -y procmail fetchmail

COPY fetchmailrc.template /home/mailer/.fetchmailrc
COPY procmailrc.template /home/mailer/.procmailrc
COPY run.sh /home/mailer/

RUN chmod 600 /home/mailer/.fetchmailrc
RUN chmod 600 /home/mailer/.procmailrc
RUN chown -R mailer:mailer /home/mailer
RUN chmod +x /home/mailer/run.sh
