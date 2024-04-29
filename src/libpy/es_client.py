# ! /usr/bin/env python
# coding=utf-8
# ******************************************************************************
# Copyright (c) Huawei Technologies Co., Ltd. 2020-2020. All rights reserved.
# licensed under the Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#     http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND, EITHER EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT, MERCHANTABILITY OR FIT FOR A PARTICULAR
# PURPOSE.
# See the Mulan PSL v2 for more details.
# Author: He Shoucheng
# Create: 2022-06-23
# ******************************************************************************/


import os
import traceback
from elasticsearch import Elasticsearch

from src.libpy.single_class import SingleClass


class EsClient(metaclass=SingleClass):
    def __init__(self):
        hosts = ["http://{0}:{1}".format(os.getenv("ES_HOST", '172.17.0.1'), os.getenv("ES_PORT", 9200))]
        self.es_handler = Elasticsearch(hosts=hosts,
                                        http_auth=(os.getenv("ES_USER"), os.getenv("ES_PASSWORD")), timeout=3600)

    def search_by_id(self, index: str, doc_id: str) -> dict:
        """
        :param index:
        :param doc_id:
        :return: {}
        """
        return self.es_handler.get(index=index, id=doc_id, ignore=404)
