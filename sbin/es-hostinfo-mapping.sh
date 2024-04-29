#!/bin/sh
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

. $CCI_SRC/container/defconfig.sh

load_service_authentication
load_cci_defaults

# check whether accounts index has created
status_code=$(curl -sSIL -u "${ES_SUPER_USER}:${ES_SUPER_PASSWORD}" -w "%{http_code}\\n" -o /dev/null http://${ES_HOST}:9200/hosts1)

if [ "$status_code" -eq 200 ]
then
	echo "hostinfo index has been created, exit."
else
	echo "begin create index."
	curl -sSH 'Content-Type: Application/json' -XPUT "http://${ES_HOST}:9200/hosts1" -u "${ES_SUPER_USER}:${ES_SUPER_PASSWORD}" -d '{
		"mappings": {
			"dynamic": false,
			"properties": {
			}
		}
	}'
fi
