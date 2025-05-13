import requests
import json
import time
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
