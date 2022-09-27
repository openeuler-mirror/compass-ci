# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM python:3.7-buster

ENV PIP_SOURCE https://pypi.tuna.tsinghua.edu.cn/simple

ARG ES_HOST
ARG ES_PORT
ARG ES_USER
ARG ES_PASSWORD
ARG SCHED_HOST
ARG SCHED_PORT

ENV ES_HOST ${ES_HOST}
ENV ES_PORT ${ES_PORT}
ENV ES_USER ${ES_USER}
ENV ES_PASSWORD ${ES_PASSWORD}
ENV SCHED_HOST ${SCHED_HOST}
ENV SCHED_PORT ${SCHED_PORT}
ENV LKP_SRC /c/lkp-tests

ENV SERVICE_PORT 20040

COPY conf/sources.list* /etc/apt/
COPY requirements.txt .

RUN apt-get -y update && \
    apt-get -y install git ruby ruby-dev make libssl-dev gcc g++ sudo uuid-runtime cpio
RUN gem sources -r https://rubygems.org/ -a https://gems.ruby-china.com/

RUN gem install faye-websocket activesupport:6.1.4.4 rest-client public_suffix:4.0.7 git

RUN umask 002 && \
    /usr/local/bin/python3 -m pip install --upgrade pip && \
    pip3 install -r ./requirements.txt -i ${PIP_SOURCE}

WORKDIR /opt/compass-ci/src/scheduled_task

EXPOSE ${SERVICE_PORT}
ENTRYPOINT gunicorn --config ./conf/gunicorn_conf.py run:app
