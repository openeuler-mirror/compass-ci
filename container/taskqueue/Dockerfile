# SPDX-License-Identifier: MulanPSL-2.0+

FROM alpine:3.11

RUN sed -i.origin 's|dl-cdn.alpinelinux.org|mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN apk add --no-cache 'gcc' 'pcre' 'libevent' 'bash'

ENV RUNTIME_DIR /c/cci/taskqueue

RUN mkdir -p $RUNTIME_DIR && \
    chown -R 1090:1090 /c

WORKDIR $RUNTIME_DIR

COPY --chown=1090:1090 taskqueue .
