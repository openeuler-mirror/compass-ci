# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM alpine:3.18

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN apk update --no-cache && \
    apk upgrade && \
    apk add --no-cache git && \
    apk add --no-cache ruby-dev make gcc g++ util-linux bash curl python3 python3-dev libffi-dev rust py3-pip

RUN /bin/bash -c 'adduser -u 1090 -D lkp'

RUN gem sources -r https://rubygems.org/ -a https://gems.ruby-china.com/

RUN umask 002 && \
    gem install bunny json activesupport:6.1.4.4 git rest-client io-console elasticsearch:7.11.1 md5sum base64

ENV PIP_SOURCE https://mirrors.huaweicloud.com/repository/pypi/simple/

RUN pip install --upgrade pip && \
    pip3 install cryptography==38

RUN apk del gcc g++

COPY --chown=1090 cbs /c/compass-ci
COPY --chown=1090 lkp-tests /c/lkp-tests

RUN echo 'umask 027' >> /home/lkp/.bashrc

RUN find / \( -name '*.crt' -o -name '*.pem' \) -a -not -name 'ca-certificates.crt' -exec ls {} \; | xargs rm -f

RUN chmod 600 /etc/ssl/certs/ca-certificates.crt
RUN chown lkp:lkp /etc/ssl/certs/ca-certificates.crt

RUN apk del rpcgen gcc gdb

RUN find / -perm -004 -regex '.*\.conf\|.*\.cnf\|.*\.cfg\|.*\.config\|.*\.xml\|.*\.properties\|.*\.yaml\|.*\.yml\|.*\.json\|.*\.sql\|.*\.ini\|.*\.key\|.*\.cacert\|.*\.log' -type f |sed -e 's/^/\"/' -e 's/$/\"/' |xargs chmod 640

RUN rm -f /bin/sh

COPY sh /bin/sh

WORKDIR /c/compass-ci/sbin
