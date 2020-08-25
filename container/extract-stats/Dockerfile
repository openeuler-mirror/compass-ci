# SPDX-License-Identifier: MulanPSL-2.0+

FROM alpine:3.11

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories &&\
    apk update &&\
    apk add --no-cache 'ruby-dev' \
    'g++' 'gcc' 'pcre' 'libevent' 'make' 'git' 'cpio' 'bash' 'grep'

RUN umask 002 &&\
    gem install rest-client activesupport git json yaml

ENV RUNTIME_DIR /c/cci/extract

RUN mkdir -p $RUNTIME_DIR && \
    chown -R 1090:1090 /c

WORKDIR $RUNTIME_DIR

COPY --chown=1090:1090 extract-stats .
