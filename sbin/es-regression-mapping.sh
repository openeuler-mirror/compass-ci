#!/bin/sh

. $CCI_SRC/container/defconfig.sh

load_service_authentication
load_cci_defaults

# check whether regression index has created
status_code=$(curl -sSIL -u "${ES_SUPER_USER}:${ES_SUPER_PASSWORD}" -w "%{http_code}\\n" -o /dev/null http://${ES_HOST}:9200/regression)

if [ "$status_code" -eq 200 ]
then
	echo "regression index has been created, exit."
else
	echo "begin create index."
	curl -sSH 'Content-Type: Application/json' -XPUT "http://${ES_HOST}:9200/regression" -u "${ES_SUPER_USER}:${ES_SUPER_PASSWORD}" -d '{
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
