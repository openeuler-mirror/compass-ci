# SPDX-License-Identifier: MulanPSL-2.0+

# 3.12 cannot install crystal
FROM alpine:3.11

MAINTAINER Wu Fenguang <wfg@mail.ustc.edu.cn>

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN apk update
RUN apk add shadow bash zsh git openssh openrc rsync crystal shards make gcc g++ tzdata sudo coreutils util-linux libffi-dev openssl-dev libtool yaml-dev vim && shards init

EXPOSE 2200
CMD ["/usr/sbin/sshd", "-D", "-p", "2200"]
