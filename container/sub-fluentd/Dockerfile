# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM fluentd-base:alpine

COPY --chown=1090:1090 docker-fluentd.conf /fluentd/etc/docker-fluentd.conf

RUN chmod 640 /fluentd/etc/docker-fluentd.conf

RUN apk update --no-cache && \
    apk upgrade

RUN for i in pem crt; do find / -name *.$i | xargs rm -rf; done

RUN adduser -u 1090 -D lkp

RUN echo "umask 027" >>/home/lkp/.bashrc

RUN rm -f /bin/sh
