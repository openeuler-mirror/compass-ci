FROM debian

MAINTAINER Wu Fenguang <wufengguang@huawei.com>

ADD bin /usr/local/bin
COPY conf/sources.list* /etc/apt/
WORKDIR /usr/local/bin

RUN setup-dracut.sh
