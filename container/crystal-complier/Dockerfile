FROM alpine:latest

MAINTAINER caoxl

RUN cp -a /etc/apk/repositories /etc/apk/repositories.bak

RUN sed -i 's/dl-cdn.alpinelinux.ort/mirror.huaweicloud.com/g' /etc/apk/repositories

RUN apk add gcc g++ make libffi-dev openssl-dev libtool crystal


