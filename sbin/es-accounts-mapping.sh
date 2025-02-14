#!/bin/sh
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

. $CCI_SRC/container/defconfig.sh

load_service_authentication
load_cci_defaults

# check whether accounts index has created
status_code=$(curl -sSIL -u "${ES_SUPER_USER}:${ES_SUPER_PASSWORD}" -w "%{http_code}\\n" -o /dev/null http://${ES_HOST}:9200/accounts)

if [ "$status_code" -eq 200 ]
then
	echo "accounts index has been created, exit."
else
	echo "begin create index."
	curl -sSH 'Content-Type: Application/json' -XPUT "http://${ES_HOST}:9200/accounts" -u "${ES_SUPER_USER}:${ES_SUPER_PASSWORD}" -d '{
    "mappings" : {
      "dynamic" : "false",
      "dynamic_templates" : [
        {
          "my_third_party_accounts" : {
            "path_match" : "my_third_party_accounts.*",
            "mapping" : {
              "enabled" : true,
              "type" : "keyword"
            }
          }
        },
        {
          "default" : {
            "match" : "*",
            "mapping" : {
              "enabled" : false,
              "type" : "object"
            }
          }
        }
      ],
      "properties" : {
        "id" : {
          "type" : "long"
        },
        "my_account" : {
          "type" : "keyword"
        },
        "my_commit_url" : {
          "type" : "keyword"
        },
        "my_email" : {
          "type" : "keyword"
        },
        "my_login_name" : {
          "type" : "keyword"
        },
        "my_name" : {
          "type" : "keyword"
        },
        "my_role" : {
          "type" : "keyword"
        },
        "my_third_party_accounts" : {
          "dynamic" : "true",
          "properties" : {
            "openeuler_username" : {
              "type" : "keyword"
            }
          }
        },
        "my_token" : {
          "type" : "keyword"
        }
      }
    }
}'
fi
