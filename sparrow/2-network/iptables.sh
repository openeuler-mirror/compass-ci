#!/bin/bash -e
if [ ! -f "/etc/firewalld/zones/public.xml" ]
then
	exit
else
	sed -i '/<zone>/a\<rule family="ipv4">\n  <source address="172.17.0.1/16" />\n  <accept />\n</rule>' /etc/firewalld/zones/public.xml
	systemctl restart firewalld
fi

