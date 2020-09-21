#!/bin/sh
# SPDX-License-Identifier: MulanPSL-2.0+

# check whether accounts index has created
status_code=$(curl -sIL -w "%{http_code}\\n" -o /dev/null http://localhost:9200/accounts)

if [ "$status_code" -eq 200 ]
then
	echo "accounts index has been created, exit."
else
	echo "begin create index."
	curl -H 'Content-Type: Application/json' -XPUT 'http://localhost:9200/accounts' -d '{
		"mappings": {
			"_doc": {
				"dynamic": false,
				"properties": {
					"uuid": {
						"type": "keyword"
					},
					"email": {
						"type": "keyword"
					}
				}
			}
		}
	}'
fi
