FROM alpine:3.11

RUN apk update && \
    apk upgrade && \
    apk add --no-cache git-daemon && \
    mkdir /git


VOLUME /git/

EXPOSE 9418

CMD ["git", "daemon", "--verbose", "--export-all", "--base-path=/git/", "--reuseaddr", "/git/"]
