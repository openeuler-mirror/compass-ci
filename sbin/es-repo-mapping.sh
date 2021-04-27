#!/bin/sh
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

. $CCI_SRC/container/defconfig.sh

load_service_authentication

# Check if "repo" index already exists.
status_code=$(curl -sSIL -u "${ES_USER}:${ES_PASSWORD}" -w "%{http_code}\n" -o /dev/null http://localhost:9200/repo)
[ $status_code -eq 200 ] && echo '"repo" index already exists.' && exit

# Create "repo" index.
echo 'Start to create "repo" index.'
curl -sSH 'Content-Type: Application/json' -XPUT 'http://localhost:9200/repo' -u "${ES_USER}:${ES_PASSWORD}" -d '
{
    "mappings": {
        "properties": {
            "git_repo": {
                "type": "keyword"
            },
            "pkgbuild_repo": {
                "type": "keyword"
            },
            "url": {
                "type": "keyword"
            },
            "fetch_time": {
                "type": "keyword"
            },
            "new_refs_time": {
                "type": "keyword"
            },
            "offset_fetch": {
                "type": "long"
            },
            "offset_new_refs": {
                "type": "long"
            },
            "priority": {
                "type": "long"
            },
            "queued": {
                "type": "boolean"
            }
        }
    }
}'
[ $? -ne 0 ] && echo 'Failed to create "repo" index.'
