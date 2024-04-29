FROM alpine:scheduler-dev

COPY repositories /etc/apk/

RUN apk add --upgrade busybox && \
    apk add --no-cache 'ruby-dev' \
    'g++' 'gcc' 'pcre' 'libevent' 'make' 'git' 'cpio' 'bash'

RUN umask 002 && \
    gem sources -r https://rubygems.org/ -a https://gems.ruby-china.com/ && \
    gem install yaml


ENV SERIAL_RUNTIME_DIR /c/cci/serial

RUN mkdir -p $SERIAL_RUNTIME_DIR && \
    chown -R 1090:1090 /c

WORKDIR $SERIAL_RUNTIME_DIR

COPY --chown=1090:1090 serial-logging .

RUN apk del gdb rpcgen
