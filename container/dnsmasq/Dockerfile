FROM alpine

RUN apk add dnsmasq

EXPOSE 67/udp 69/udp

CMD ["dnsmasq", "-k"]
