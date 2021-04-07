#!/bin/sh

# check whether regression index has created
status_code=$(curl -sSIL -w "%{http_code}\\n" -o /dev/null http://localhost:9200/regression)

if [ "$status_code" -eq 200 ]
then
	echo "regression index has been created, exit."
else
	echo "begin create index."
	curl -sSH 'Content-Type: Application/json' -XPUT 'http://localhost:9200/regression' -d '{
		"mappings": {
			"dynamic": false,
			"properties": {
				"error_id": {
					"type": "keyword"
				},
				"job_id": {
					"type": "keyword"
				}
			}
		}
	}'
fi
