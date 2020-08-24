# SPDX-License-Identifier: MulanPSL-2.0+

FROM alpine:3.11

RUN sed -i.origin 's|dl-cdn.alpinelinux.org|mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN apk add dnsmasq
RUN mkdir -p /var/log/dnsmasq

EXPOSE 67/udp 69/udp

CMD ["dnsmasq", "-k"]
