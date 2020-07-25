FROM alpine:3.11

RUN apk update && \
    apk upgrade && \
    apk add --no-cache git && \
    apk add ruby-dev make gcc g++ && \
    gem install bunny json

