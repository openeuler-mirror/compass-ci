FROM alpine:3.8

RUN apk update && \
    apk upgrade && \
    apk add --no-cache git && \
    apk add ruby-dev make gcc g++

RUN umask 002 && \
    gem install bunny json PriorityQueue --no-rdoc --no-ri

