# SPDX-License-Identifier: MulanPSL-2.0+

FROM alpine

RUN apk add dnsmasq
RUN mkdir -p /var/log/dnsmasq

# dhcp-lease-max:
# - limits dnsmasq to the specified maximum number of DHCP leases.
# - the default is 1000.
RUN sed -i 's/.*dhcp-lease-max=.*/dhcp-lease-max=100000/g' /etc/dnsmasq.conf

EXPOSE 67/udp 69/udp

CMD ["dnsmasq", "-k"]
