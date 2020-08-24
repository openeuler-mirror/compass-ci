FROM alpine:3.11

RUN sed -i.origin 's|dl-cdn.alpinelinux.org|mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN apk update

RUN apk add --no-cache 'ruby-dev' \
    'g++' 'gcc' 'pcre' 'libevent' 'make' 'git' 'cpio' 'bash'

RUN umask 002 &&\
    gem install rest-client && \
    gem install activesupport && \
    gem install git && \
    gem install json && \
    gem install yaml


ENV MONITOR_RUNTIME_DIR /c/cci/monitor

RUN mkdir -p $MONITOR_RUNTIME_DIR && \
    chown -R 1090:1090 /c

WORKDIR $MONITOR_RUNTIME_DIR

COPY --chown=1090:1090 monitoring .
