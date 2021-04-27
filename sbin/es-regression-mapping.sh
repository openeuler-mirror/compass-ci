#!/bin/sh

. $CCI_SRC/container/defconfig.sh

load_service_authentication

# check whether regression index has created
status_code=$(curl -sSIL -u "${ES_USER}:${ES_PASSWORD}" -w "%{http_code}\\n" -o /dev/null http://localhost:9200/regression)

if [ "$status_code" -eq 200 ]
then
	echo "regression index has been created, exit."
else
	echo "begin create index."
	curl -sSH 'Content-Type: Application/json' -XPUT 'http://localhost:9200/regression' -u "${ES_USER}:${ES_PASSWORD}" -d '{
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
