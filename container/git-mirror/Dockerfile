FROM alpine:3.11

RUN apk update && \
    apk upgrade && \
    apk add --no-cache git && \
    apk add ruby-dev make gcc g++

Run umask 002 && \
    gem install bunny json

