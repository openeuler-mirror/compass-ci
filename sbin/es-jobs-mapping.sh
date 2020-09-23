#!/bin/sh
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

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

# Determine whether jobs index has created
status_code=$(curl -sIL -w "%{http_code}\n" -o /dev/null http://localhost:9200/jobs)

if [ $status_code -eq 200 ]
then
	echo "jobs index has create, exit."
else
	echo "jobs index not exists, begin create index."
	curl -H 'Content-Type: Application/json' -XPUT 'http://localhost:9200/jobs' -d '{
		    "mappings": {
		      "_doc": {
		      "dynamic_templates": [
		          {
		            "pp": {
		              "path_match": "pp.*.*",
		              "mapping": {
		                "type": "keyword",
		                "enabled": true
		              }
		            }
		          },
		          {
		            "default": {
		              "match": "*",
		              "unmatch": "pp",
		              "path_unmatch": "pp.*",
		              "mapping": {
		                "type": "object",
		                "enabled": false
		              }
		            }
		          }
		        ],
		        "properties": {
		          "suite": {
		            "type": "keyword"
		          },
		          "category": {
		            "type": "keyword"
		          },
		          "hw.nr_threads": {
		            "type": "keyword"
		          },
		          "queue": {
		            "type": "keyword"
		          },
		          "testbox": {
		            "type": "keyword"
		          },
		          "tbox_group": {
		            "type": "keyword"
		          },
		          "submit_id": {
		            "type": "keyword"
		          },
		          "id": {
		            "type": "keyword"
		          },
		          "hw.arch": {
		            "type": "keyword"
		          },
		          "hw.model": {
		            "type": "keyword"
		          },
		          "hw.nr_node": {
		            "type": "integer"
		          },
		          "hw.nr_cpu": {
		            "type": "integer"
		          },
		          "hw.memory": {
		            "type": "keyword"
		          },
		          "os": {
		            "type": "keyword"
		          },
		          "os_arch": {
		            "type": "keyword"
		          },
		          "os_version": {
		            "type": "keyword"
		          },
		          "upstream_repo": {
		            "type": "keyword"
		          },
		          "upstream_commit": {
		            "type": "keyword"
		          },
		          "enqueue_time": {
		            "type": "date",
		            "format": "yyyy-MM-dd HH:mm:ss"
		          },
		          "dequeue_time": {
		            "type": "date",
		            "format": "yyyy-MM-dd HH:mm:ss"
		          },
		          "user": {
		            "type": "keyword"
		          },
		          "job_state": {
		            "type": "keyword"
		          },
		          "start_time": {
		            "type": "date",
		            "format": "yyyy-MM-dd HH:mm:ss"
		          },
		          "end_time": {
		            "type": "date",
		            "format": "yyyy-MM-dd HH:mm:ss"
		          }
		        }
		      }
		    }
		  }'
	  if [ $? -ne 0 ]
	  then
		  echo "create jobs index failed."
	  fi
fi
