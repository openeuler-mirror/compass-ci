# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM alpine:latest

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories
RUN apk update

RUN umask 002 \
  && adduser sshr -u 1090 -g 1090 -D \
  && mkdir -p /home/sshr/.ssh \
  && chown -R sshr:sshr /home/sshr \
  && chmod 700 /home/sshr/.ssh

RUN apk add openssh augeas \
  && rm -fr /var/cache/apk/*

COPY known_auth_keys /home/sshr/.ssh/authorized_keys

RUN chown -R sshr:sshr /home/sshr/.ssh/authorized_keys \
  && chmod 600 /home/sshr/.ssh/authorized_keys \
  && passwd -u sshr

EXPOSE 20000-22000
EXPOSE 22

COPY entry.sh /entry.sh
ENTRYPOINT ["/entry.sh"]

CMD ["/usr/sbin/sshd", "-D", "-e", "-f", "/etc/ssh/sshd_config"]
