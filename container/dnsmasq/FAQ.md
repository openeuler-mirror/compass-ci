## find IP address out according MAC
```
1. find your pxe server container (usually named dnsmasq)
2. docker exec -it dnsmasq sh
3. grep [testbox_IP] /var/lib/misc/dnsmasq.leases
4. find your testbox MAC
```

## Add dnsmasq service logs
```
1. add log config in dnsmasq.d/dnsmasq.conf
	log-queries
	log-facility=/var/log/dnsmasq/dnsmasq.log
2. rerun script run: ./run
3. docker exec -it dnsmasq sh
4. tail -f /var/log/dnsmasq/dnsmasq.log
5. check the output on your terminal
```

## TODO
