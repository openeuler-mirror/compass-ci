#!/bin/sh
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

. $CCI_SRC/container/defconfig.sh

load_service_authentication

# check whether accounts index has created
status_code=$(curl -sSIL -u "${ES_USER}:${ES_PASSWORD}" -w "%{http_code}\\n" -o /dev/null http://localhost:9200/accounts)

if [ "$status_code" -eq 200 ]
then
	echo "accounts index has been created, exit."
else
	echo "begin create index."
	curl -sSH 'Content-Type: Application/json' -XPUT 'http://localhost:9200/accounts' -u "${ES_USER}:${ES_PASSWORD}" -d '{
		"mappings": {
			"dynamic": false,
			"properties": {
				"my_commit_url": {
					"type": "keyword"
				},
				"my_token": {
					"type": "keyword"
				},
				"my_email": {
					"type": "keyword"
				},
				"my_name": {
					"type": "keyword"
				},
				"my_login_name": {
					"type": "keyword"
				}
			}
		}
	}'
fi
