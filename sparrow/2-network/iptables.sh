#!/bin/bash

PUB_IFACE=`ip route get 1.2.3.4 | awk '{print $5; exit}'`
INT_IFACE=br0

BR0_SUBNET=192.168.177.0/24

#iptables -t nat -F
iptables -t nat -A POSTROUTING -o $PUB_IFACE -s $BR0_SUBNET -j MASQUERADE
iptables -t nat -A POSTROUTING -o $INT_IFACE -d $BR0_SUBNET -j MASQUERADE
