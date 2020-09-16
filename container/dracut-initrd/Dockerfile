# SPDX-License-Identifier: MulanPSL-2.0+

FROM debian

MAINTAINER Wu Fenguang <wfg@mail.ustc.edu.cn>

ADD bin /usr/local/bin
COPY conf/sources.list* /etc/apt/
COPY conf/add-cifs.conf /etc/dracut.conf.d/
WORKDIR /usr/local/bin

RUN setup-dracut.sh
