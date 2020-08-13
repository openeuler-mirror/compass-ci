# SPDX-License-Identifier: MulanPSL-2.0+

FROM alpine

RUN apk add dnsmasq
RUN mkdir -p /var/log/dnsmasq

EXPOSE 67/udp 69/udp

CMD ["dnsmasq", "-k"]
