#!/bin/sh
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

. $CCI_SRC/container/defconfig.sh

load_service_authentication

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
status_code=$(curl -sSIL -u "${ES_USER}:${ES_PASSWORD}" -w "%{http_code}\n" -o /dev/null http://localhost:9200/jobs)

if [ $status_code -eq 200 ]
then
	echo "jobs index has create, exit."
else
	echo "jobs index not exists, begin create index."
	curl -sSH 'Content-Type: Application/json' -XPUT 'http://localhost:9200/jobs' -u "${ES_USER}:${ES_PASSWORD}" -d '{
		    "mappings": {
		      "dynamic": false,
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
		          "pp": {
		            "dynamic": true,
		            "properties": {}
		          },
			  "pp.sleep":{
		            "type": "object",
		            "enabled": false
			  },
		          "suite": {
		            "type": "keyword"
		          },
		          "submit_time": {
		            "type": "date"
		          },
		          "errid": {
			    "type": "text"
			  },
		          "time": {
			    "type": "date"
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
		          "subqueue": {
			    "type": "keyword"
		          },
		          "all_params_md5": {
			    "type": "keyword"
			  },
		          "pp_params_md5": {
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
		          "group_id": {
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
		          "base_commit": {
		            "type": "keyword"
		          },
		          "nr_run": {
		            "type": "integer"
		          },
		          "my_email": {
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
		          "submit_date": {
		            "type": "date",
		            "format": "yyyy-MM-dd"
		          },
		          "user": {
		            "type": "keyword"
		          },
		          "job_state": {
		            "type": "keyword"
		          },
		          "job_stage": {
			    "type": "keyword"
			  },
		          "job_health": {
			    "type": "keyword"
			  },
		          "last_success_stage": {
			    "type": "keyword"
			  },
		          "tags": {
		            "type": "text"
		          },
		          "start_time": {
		            "type": "date"
		          },
		          "end_time": {
		            "type": "date"
		          }
		        }
		    }
		  }'
	  if [ $? -ne 0 ]
	  then
		  echo "create jobs index failed."
	  else
		  echo "set index.mapping.total_fields.limit: 10000"
		  curl -sS -XPUT 127.0.0.1:9200/jobs/_settings -u "${ES_USER}:${ES_PASSWORD}" -H 'Content-Type: application/json' \
		       -d '{"index.mapping.total_fields.limit": 10000}'
	  fi
fi
