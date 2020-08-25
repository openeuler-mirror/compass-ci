# SPDX-License-Identifier: MulanPSL-2.0+

FROM alpine:3.11

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN apk update && \
    apk upgrade && \
    apk add --no-cache git-daemon && \
    mkdir /git


VOLUME /git/

EXPOSE 9418

CMD ["git", "daemon", "--verbose", "--export-all", "--base-path=/git/", "--reuseaddr", "/git/"]
