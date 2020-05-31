#!/bin/bash

gem install git activesupport rest-client cucumber

adduser -u 1090 lkp

cat >> /etc/sysctl.conf <<EOF
net.ipv4.ip_forward=1
vm.max_map_count=655360
EOF
