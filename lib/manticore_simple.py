import requests
import json
import time
from log_config import logger, StructuredLogger
from typing import Dict, List, Union, Optional

class ManticoreClient:
    def __init__(self, host="localhost", port=9308):
        self.base_url = f"http://{host}:{port}"

    def insert(self, index: str, id: int, document: dict) -> bool:
        """插入文档"""
        return self._request("insert", index, id, document)
    
    def replace(self, index: str, id: int, document: dict) -> bool:
        """替换文档""" 
        return self._request("replace", index, id, document)

    def update(self, index: str, id: int, document: dict) -> bool:
        """部分更新文档（仅修改指定字段）"""
        return self._request("update", index, id, document)

    def search(self,
             table: str,
             query: dict,
             limit: int = 100,
             options: Optional[dict] = None) -> Optional[List[Dict]]:
        """
        Manticore 官方标准搜索方法

        :param table: 要查询的表名
        :param query: 查询 DSL (支持 query_string/match/bool 等)
        :param limit: 返回结果数量 (默认100)
        :param options: 高级选项 (scroll/列过滤等)
        :return: 文档内容字典列表
        """
        try:
            request_body = {
                "table": table,
                "query": query,
                "limit": limit
            }

            if options:
                request_body["options"] = options

            resp = requests.post(
                f"{self.base_url}/search",
                json=request_body,
                timeout=5
            )

            if resp.status_code != 200:
                logger.error(f"Search request failed with status code {resp.status_code}: {resp.text}")
                return None

            result = resp.json()
            return [
                hit.get('_source', {})
                for hit in result.get('hits', {}).get('hits', [])
                if '_source' in hit
            ]

        except requests.exceptions.RequestException:
            return None

    def replace_with_retry(self, index: str, id: int, document: dict, retries: int = 3) -> bool:
        """带重试机制的替换操作"""
        for i in range(retries):
            if self.replace(index, id, document):
                return True
            time.sleep(2 ** i)
        return False

    def bulk_replace(self, index: str, documents: Dict[int, dict]) -> bool:
        """批量替换文档"""
        try:
            bulk_body = []
            for doc_id, doc in documents.items():
                bulk_body.append(json.dumps({"replace": {"_index": index, "_id": doc_id}}))
                bulk_body.append(json.dumps(doc))
            
            resp = requests.post(
                f"{self.base_url}/bulk",
                data="\n".join(bulk_body),
                headers={"Content-Type": "application/x-ndjson"},
                timeout=10
            )
            return resp.status_code == 200
        except requests.exceptions.RequestException:
            return False

    def _request(self, endpoint: str, index: str, id: int, doc: dict) -> bool:
        try:
            resp = requests.post(
                f"{self.base_url}/{endpoint}",
                json={"index": index, "id": id, "doc": doc},
                timeout=3
            )
            return resp.status_code == 200
        except requests.exceptions.RequestException:
            return False
