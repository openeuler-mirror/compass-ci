# SPDX-License-Identifier: MulanPSL-2.0+

FROM alpine:3.11

RUN sed -i.origin 's|dl-cdn.alpinelinux.org|mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN apk update && \
    apk upgrade && \
    apk add --no-cache git-daemon && \
    mkdir /git


VOLUME /git/

EXPOSE 9418

CMD ["git", "daemon", "--verbose", "--export-all", "--base-path=/git/", "--reuseaddr", "/git/"]
