# SPDX-License-Identifier: MulanPSL-2.0+

FROM alpine:3.11

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN apk add dnsmasq
RUN mkdir -p /var/log/dnsmasq

EXPOSE 67/udp 69/udp

CMD ["dnsmasq", "-k"]
