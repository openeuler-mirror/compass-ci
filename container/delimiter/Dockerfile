# SPDX-License-Identifier: MulanPSL-2.0+

FROM alpine:3.11

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories && \
    apk update && \
    apk add --no-cache 'ruby-dev' \
    'g++' 'gcc' 'pcre' 'libevent' 'make' 'git' 'bash' 'grep'

RUN umask 002 && \
    echo ':sources: ["http://rubygems.org"]' >> ~/.gemrc && \
    gem install rest-client activesupport git json yaml threadpool elasticsearch faye-websocket
