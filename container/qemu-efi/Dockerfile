# SPDX-License-Identifier: MulanPSL-2.0+

FROM debian

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends apt-utils > /dev/null 2>&1 && \
    apt-get install -y qemu-efi-aarch64
