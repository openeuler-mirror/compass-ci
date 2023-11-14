#!/bin/sh
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

. $CCI_SRC/container/defconfig.sh

load_service_authentication
load_cci_defaults

# check whether job_resource index has created
status_code=$(curl -sSIL -u "${ES_SUPER_USER}:${ES_SUPER_PASSWORD}" -w "%{http_code}\\n" -o /dev/null http://${ES_HOST}:9200/job_resource)

if [ "$status_code" -eq 200 ]
then
	echo "job_resource index has been created, exit."
else
	echo "begin create job_resource index."
	curl -sSH 'Content-Type: Application/json' -XPUT "http://${ES_HOST}:9200/job_resource" -u "${ES_SUPER_USER}:${ES_SUPER_PASSWORD}" -d '{
    "mappings" : {
      "dynamic" : "false",
      "properties" : {
        "cpu" : {
          "type" : "keyword"
        },
        "mem" : {
          "type" : "keyword"
        }
      }
    }
}'
fi
