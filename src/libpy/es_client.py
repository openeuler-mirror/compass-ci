import os

from elasticsearch import Elasticsearch


class EsClient:
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
