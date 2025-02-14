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
# Update: 2025-01-11
# ******************************************************************************/


import os
import traceback
import json
from elasticsearch import Elasticsearch


class EsClient():
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

    def update_by_id(self, index: str, doc_id: str, body: dict) -> dict:
        """
        Update a document by its ID.
        :param index: Index name
        :param doc_id: Document ID
        :param body: Document content to update (as a dictionary)
        :return: Response from the update operation
        """
        return self.es_handler.index(index=index, id=doc_id, body=body)

    def delete_by_id(self, index: str, doc_id: str) -> dict:
        """
        Delete a document by its ID.
        :param index: Index name
        :param doc_id: Document ID
        :return: Response from the delete operation
        """
        return self.es_handler.delete(index=index, id=doc_id, ignore=404)

    def create_index(self, index: str, body: dict = None) -> dict:
        """
        Create an index.
        :param index: Index name
        :param body: Index mappings and settings (optional)
        :return: Response from the index creation operation
        """
        return self.es_handler.indices.create(index=index, body=body, ignore=400)  # ignore=400 to ignore errors if the index already exists

    def delete_index(self, index: str) -> dict:
        """
        Delete an index.
        :param index: Index name
        :return: Response from the delete operation
        """
        return self.es_handler.indices.delete(index=index, ignore=404)  # ignore=404 to ignore errors if the index does not exist

    def bulk_index(self, index: str, data: list) -> dict:
        """
        Perform bulk indexing of documents.
        :param index: Index name
        :param data: List of documents, formatted as [{"id": "1", "name": "John Doe"}, {"id": "2", "name": "Jane Smith"}]
        :return: Response from the bulk operation
        """
        actions = []
        for item in data:
            actions.append({"index": {"_index": index, "_id": item.get("id")}})
            actions.append(item)
        return self.es_handler.bulk(index=index, body=actions)

    def search_by_query(self, index: str, query: dict) -> dict:
        """
        Search for documents based on a query.
        :param index: Index name
        :param query: Query conditions (as a dictionary)
        :return: Query results
        """
        # Perform the search query
        response = self.es_handler.search(index=index, body=query)
        # Extract relevant information from the response
        total_hits = response['hits']['total']['value']  # Total number of hits
        hits = response['hits']['hits']  # List of documents

        # Format the results
        results = {
            "documents": [hit["_source"] for hit in hits]  # Extract the '_source' field
        }
        return results["documents"]


