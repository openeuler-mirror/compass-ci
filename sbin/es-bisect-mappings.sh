#!/bin/sh
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2025 Huawei Technologies Co., Ltd. All rights reserved.

. $CCI_SRC/container/defconfig.sh

load_service_authentication
load_cci_defaults

# Determine whether curl is installed. If not, install curl.
if ! [ -x "$(command -v curl)" ]
then
	echo "curl not exists, try to install."
	if [ -x "$(command -v apk)" ]
	then
		apk add install -y curl
	elif [ -x "$(command -v yum)" ]
	then
		yum install -y curl
	elif [ -x "$(command -v apt-get)" ]
	then
		apt-get install -y curl
	fi
else
	echo "curl has install."
fi

# Determine whether curl is installed successfully
if [ $? -ne 0 ]
then
	echo "curl install failed, exit."
	exit
fi

# Determine whether bisect index has created
status_code=$(curl -sSIL -u "${ES_SUPER_USER}:${ES_SUPER_PASSWORD}" -w "%{http_code}\n" -o /dev/null http://${ES_HOST}:9200/bisect-task)

if [ $status_code -eq 200 ]
then
	echo "bisect_task index has create, exit."
	curl -sSH 'Content-Type: Application/json' -XPUT "http://${ES_HOST}:9200/bisect_task/_mapping" -u "${ES_SUPER_USER}:${ES_SUPER_PASSWORD}" -d '{
	"properties": {
		"id": {"type": "keyword"},
		"bad_job_id": {"type": "keyword"},
		"error_id": {"type": "keyword"},
		"bisect_status": {"type": "keyword"},
		"repo": {"type": "keyword"},
		"bad_commit": {"type": "keyword"},
		"work_dir": {"type": "keyword"},
		"bisect_error": {"type": "keyword"},
		"all_errors": {"type": "keyword"},
		"upstream_url": {"type": "keyword"},
		"pkgbuild_repo": {"type": "keyword"},
		"first_bad_commit_result_root": {"type": "keyword"}
	}}'
else
	echo "bisect_task index not exists, begin create index."
	curl -sSH 'Content-Type: Application/json' -XPUT 'http://localhost:9200/bisect_task' -u "${ES_USER}:${ES_PASSWORD}" -d '{
	    "settings": {
        	"number_of_shards": 1,
        	"number_of_replicas": 1
    		},
    	"mappings": {
        "properties": {
		"id": {"type": "keyword"},
		"bad_job_id": {"type": "keyword"},
		"errid": {"type": "keyword"},
		"bisect_status": {"type": "keyword"},
		"repo": {"type": "keyword"},
		"bad_commit": {"type": "keyword"},
		"work_dir": {"type": "keyword"},
		"bisect_error": {"type": "keyword"},
		"all_errors": {"type": "keyword"},
		"upstream_url": {"type": "keyword"},
		"pkgbuild_repo": {"type": "keyword"},
		"first_bad_commit_result_root": {"type": "keyword"}
        	}
		}
	}'
	if [ $? -ne 0 ]
	  then
		  echo "create bisect_task index failed."
	  else
		  echo "set index.mapping.total_fields.limit: 10000"
		  curl -sS -XPUT "${ES_HOST}":9200/bisect_task/_settings -u "${ES_SUPER_USER}:${ES_SUPER_PASSWORD}" -H 'Content-Type: application/json' \
		       -d '{"index.mapping.total_fields.limit": 10000}'
	fi
fi
