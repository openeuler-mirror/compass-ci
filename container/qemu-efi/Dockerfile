# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM debian:buster

ARG UEFI

ENV DEBIAN_FRONTEND noninteractive

COPY conf/sources.list* /etc/apt/
RUN apt-get clean && \
    apt-get update && \
    apt-get install -y $UEFI 2>/dev/null
