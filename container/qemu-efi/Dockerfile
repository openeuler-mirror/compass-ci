# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM debian

ENV DEBIAN_FRONTEND noninteractive

COPY conf/sources.list* /etc/apt/
RUN apt-get update && \
    apt-get install -y --no-install-recommends apt-utils > /dev/null 2>&1 && \
    apt-get install -y qemu-efi-aarch64
