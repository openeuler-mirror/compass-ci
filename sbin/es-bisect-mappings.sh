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
	exit
else
	echo "curl has install."
fi

# Define a string for bisect_task properties
ROPERTIES="{
   \"id\": {\"type\": \"keyword\"}, # 当前 task 的 id 而不是 job 的
   \"bad_job_id\": {\"type\": \"keyword\"}, # 需要 bisect 的 job_id
   \"error_id\": {\"type\": \"keyword\"}, # 需要 bisect 的 error_id 需要做去重,
   需要考虑是一个自增列表还是现有的黑白名单机制
   "bisect_metric": {\"type\": \"keyword\"}, # 只对性能适用
   "bisect_status": {
     "type": "keyword",
     "values": ["pending", "running", "paused", "success", "failed", "retrying"]
   },
   \"repo\": {\"type\": \"keyword\"}, # 原始 job 的仓库地址
   \"bisect_suite\": {\"type\": \"keyword\"}, # 原始 job suite 用于数据分析
   \"bad_commit\": {\"type\": \"keyword\"}, # 通过 bisect 得出的 commit 结果
   \"first_bad_id\": {\"type\": \"keyword\"}, # bad commit 所对应的 job id
   \"first_result_root\": {\"type\": \"text\"}, # bad commit 所对应的结果目录
   \"work_dir\": {\"type\": \"text\"}, # 整个 bisect 运行的路径位置
   \"start_time\": {\"type\": \"date\"}, # bisect 开始时间不包含寻找 good commit
   \"end_time\": {\"type\": \"date\"}, # bisect 结束时间
   "priority_level": {"type": "integer"}, # 数值越大优先级越高（如 0-低，1-中，2-高
   \"bisect_range\": {\"type\": \"text\"}, 
   "timeout": {"type": "integer"},  # 超时时间（秒）
   "job_commit_mappings": {
     "type": "nested",
     "properties": {
       "job_id": {"type": "keyword"},          # 关联的 Job ID
       "commit_hash": {"type": "keyword"},     # 关联的 Commit Hash
       "metric_vaule": {"type": "text"},			 # 性能测试 类型需要继续考虑
       "result_root": {"type": "keyword"},     # 该 Job 对应的结果目录
       "status": {"type": "keyword"},          # Job 状态（如 bad/good）
       "timestamp": {"type": "date"}           # 执行时间戳
    }
  }
}"

PROPERTIES="{
			 \"id\": {\"type\": \"keyword\"},
			 \"bad_job_id\": {\"type\": \"keyword\"},
			 \"error_id\": {\"type\": \"keyword\"},
			 \"bisect_status\": {\"type\": \"keyword\"},
			 \"repo\": {\"type\": \"keyword\"},
			 \"bad_commit\": {\"type\": \"keyword\"},
			 \"work_dir\": {\"type\": \"keyword\"},
			 \"bisect_error\": {\"type\": \"keyword\"},
			 \"all_errors\": {\"type\": \"keyword\"},
			 \"upstream_url\": {\"type\": \"keyword\"},
			 \"pkgbuild_repo\": {\"type\": \"keyword\"},
			 \"first_bad_commit_result_root\": {\"type\": \"keyword\"},
			 \"start_time\": {\"type\": \"date\"},
			 \"end_time\": {\"type\": \"date\"},
			 \"all_job_id\": {\"type\": \"text\"},
			 \"bisect_range\": {\"type\": \"text\"}
}"

INDEX_NAME="bisect_task"

# Determine whether bisect index has created
status_code=$(curl -sSIL -u "${ES_SUPER_USER}:${ES_SUPER_PASSWORD}" -w "%{http_code}\n" -o /dev/null http://${ES_HOST}:9200/${INDEX_NAME})

if [ $status_code -eq 200 ]
then
	echo "bisect_task index has create, exit."
	curl -sSH 'Content-Type: Application/json' \
	     -XPUT "http://${ES_HOST}:9200/${INDEX_NAME}/_mapping" \
	     -u "${ES_SUPER_USER}:${ES_SUPER_PASSWORD}" \
	     -d "{
		\"properties\": $PROPERTIES
		}"
else
	echo "bisect_task index not exists, begin create index."
	curl -sSH 'Content-Type: Application/json' \
	     -XPUT "http://localhost:9200/${INDEX_NAME}" \
	     -u "${ES_USER}:${ES_PASSWORD}" \
	     -d "{
	    	\"settings\": {
        	\"number_of_shards\": 1,
        	\"number_of_replicas\": 1
    		},
		\"mappings\": {
		\"properties\": $PROPERTIES
		}}"
	if [ $? -ne 0 ]
	  then
		  echo "create bisect_task index failed."
	  else
		  echo "set index.mapping.total_fields.limit: 10000"
		  curl -sS -XPUT "${ES_HOST}":9200/${INDEX_NAME}/_settings \
			   -u "${ES_SUPER_USER}:${ES_SUPER_PASSWORD}" -H 'Content-Type: application/json' \
		           -d '{"index.mapping.total_fields.limit": 10000}'
	fi
fi
