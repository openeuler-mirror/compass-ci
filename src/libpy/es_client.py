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

    def get_cluster_health(self) -> dict:
        """
        :return: {}
        """
        return self.es_handler.cluster.health()

    def search_by_id(self, index: str, doc_id: str) -> dict:
        """
        :param index:
        :param doc_id:
        :return: {}
        """
        return self.es_handler.get(index=index, id=doc_id, ignore=404)

    def delete_by_id(self, index: str, doc_id: str) -> dict:
        """
        :param index:
        :param doc_id:
        :return: {}
        """
        return self.es_handler.delete(index=index, id=doc_id, ignore=409, refresh=True)

    def delete_by_query(self, index: str, query: dict = None) -> dict:
        """
        :param index:
        :param doc_id:
        :return: {}
        """
        return self.es_handler.delete_by_query(index=index, body=query, ignore=409, refresh=True)

    def insert_document_with_id(self, index: str, doc_id: str, document: dict):
        """
        Creates a new document in the index. Returns a 409 response when a document with
        a same ID already exists in the index. and mast input id
        :param doc_id:
        :param index:
        :param document:
        :return:
        """
        return self.es_handler.index(index=index, id=doc_id, body=document, ignore=[400, 409], refresh=True)

    def insert_document(self, index: str, document: dict):
        """
        Creates or updates a document in an index, no need input id
        :param index:
        :param document:
        :return:
        """
        return self.es_handler.index(index=index, body=document, ignore=[400, 409], refresh=True)

    def update_document_by_id(self, index: str, doc_id: str, document: dict):
        """
        updates a document in an index, it should input id
        :param doc_id:
        :param index:
        :param document:
        :return:
        """
        doc = {"doc": document}
        return self.es_handler.update(index=index, id=doc_id, body=doc, refresh=True)

    def search_raw(self, index: str, query_body: dict) -> dict:
        """
        :param index:
        :param query_body:
        :return:
        """
        return self.es_handler.search(index=index, body=query_body)

    def search(self, index: str, query_body: dict = None, source: list = None, size: int = None, should: dict = None):
        """
        :param index:
        :param query_body:
        :param source:
        :param size:
        :param should:
        :return:
        """
        if not source:
            source = []

        if not size:
            size = 10

        if not query_body:
            return self.es_handler.search(index=index, _source=source, size=10000).get("hits").get("hits")

        musts = []
        for key, value in query_body.items():
            musts.append({
                "term": {
                    key: value
                }
            })
        shoulds = []
        if should:
            for k, v in should.items():
                shoulds.append({
                    "terms": {
                        k: v
                    }
                })
        final_query_body = {
            "query":
                {
                    "bool": {
                        "must": musts,
                        "should": shoulds,
                        "minimum_should_match": len(shoulds)
                    }
                }
        }
        return self.es_handler.search(index=index, body=final_query_body, _source=source, size=size
                                      ).get("hits").get("hits")

    def search_one(self, index: str, query_body: dict, sorted_key: str, order_by: str = "asc",
                   source: list = None, should: dict = None, exists: list = None, return_matchs: bool = False):
        """
        :param index:
        :param query_body:
        :param sorted_key:
        :param order_by:
        :param source:
        :param should:
        :param exists:
        :param return_matchs:
        :return:
            success:
                {'_id': '58fd230e-0354-11ed-bbb0-0242ac11003e',
                 '_index': 'builds',
                 '_score': None,
                 '_source': {'build_id': '58fd230e-0354-11ed-bbb0-0242ac11003e',
                             'build_target': {'architecture': 'aarch64',
                                              'os_variant': 'openeuler:20.03-LTS-SP1'},
                             ...
                             'status': 'init'},
                 '_type': '_doc',
                 'sort': [1657760832347]}
            fail:
                {}
        """
        musts = []
        if query_body:
            for key, value in query_body.items():
                musts.append({
                    "term": {
                        key: value
                    }
                })
        if exists:
            for exists_key in exists:
                musts.append({
                    "exists": {
                        "field": exists_key
                    }
                })
        shoulds = []
        if should:
            for k, v in should.items():
                shoulds.append({
                    "terms": {
                        k: v
                    }
                })
        final_query_body = {
            "query": {
                "bool": {
                    "must": musts,
                    "should": shoulds,
                    "minimum_should_match": len(shoulds)
                }
            },
            "sort": [
                {
                    sorted_key: {
                        "order": order_by
                    }
                }
            ]
        }
        if not source:
            source = []
        result = self.es_handler.search(
            index=index, body=final_query_body, _source=source, ignore=400).get("hits", {}).get("hits", [])
        if result:
            if return_matchs:
                return result
            return result[0]
        return {}

    def search_count(self, index: str, query_body: dict, should: dict = None):
        musts = []
        for key, value in query_body.items():
            musts.append({
                "term": {
                    key: value
                }
            })
        shoulds = []
        if should:
            for k, v in should.items():
                shoulds.append({
                    "terms": {
                        k: v
                    }
                })
        final_query_body = {
            "query": {
                "bool": {
                    "must": musts,
                    "should": shoulds,
                    "minimum_should_match": len(shoulds)
                }
            },
        }
        return self.es_handler.count(index=index, body=final_query_body).get("count")
