#!/bin/sh
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

. $CCI_SRC/container/defconfig.sh

load_service_authentication

curl -sSH 'Content-Type: Application/json' -XPUT 'http://localhost:9200/compat-software-info' -u "${ES_USER}:${ES_PASSWORD}" -d '{
		"mappings": {
			"dynamic": false,
			"properties": {
				"os": {
					"type": "keyword"
				},
				"arch": {
					"type": "keyword"
				},
				"srpm_addr": {
					"type": "keyword"
				},
				"rpmbuild_result_url": {
					"type": "keyword"
				},
				"property": {
					"type": "keyword"
				},
				"result_url": {
					"type": "keyword"
				},
				"result_root": {
					"type": "keyword"
				},
				"uninstall": {
					"type": "keyword"
				},
				"libs": {
					"type": "keyword"
				},
				"bin": {
					"type": "keyword"
				},
				"type": {
					"type": "keyword"
				},
				"softwareName": {
					"type": "keyword"
				},
				"install": {
					"type": "keyword"
				},
				"version": {
					"type": "keyword"
				},
				"downloadLink": {
					"type": "keyword"
				}
			}
		}
	}'
if [ $? -ne 0 ]
then
	echo "create index failed."
else
	echo "set index.mapping.total_fields.limit: 1000"
	curl -sS -XPUT 127.0.0.1:9200/compat-software-info/_settings -u "${ES_USER}:${ES_PASSWORD}" -H 'Content-Type: application/json' \
		-d '{"index.mapping.total_fields.limit": 1000}'
fi
