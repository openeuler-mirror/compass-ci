import requests
import json
import time
import traceback
from log_config import logger
from typing import Dict, List, Union, Optional

class ManticoreClient:
    def __init__(self, host="localhost", port=9308):
        self.base_url = f"http://{host}:{port}"

    def insert(self, index: str, id: int, document: dict) -> bool:
        """Insert document"""
        if "id" in document:
            logger.warning("Document contains redundant id field, removing")
            document = {k: v for k, v in document.items() if k != "id"}
            
        logger.debug(f"DEBUG - Inserting document | Index={index}, ID={id}")
        logger.debug(f"DEBUG - Document content: {json.dumps(document, indent=2)}")
        
        result = self._request("insert", index, id, document)
        
        logger.debug(f"DEBUG - Insert result: {result}")
        
        return result
    
    def replace(self, index: str, id: int, document: dict) -> bool:
        """替换文档""" 
        return self._request("replace", index, id, document)

    def update(self, index: str, id: int, document: dict) -> bool:
        """部分更新文档（仅修改指定字段）"""
        return self._request("update", index, id, document)

    def search(self,
               index: str,
               query: dict,
               limit: int = 100,
               options: Optional[dict] = None,
               sort: Optional[list] = None) -> Optional[List[Dict]]:
        """
        Manticore 标准 SQL 风格搜索方法
        """
        # DEBUG: 打印请求详情
        logger.debug(f"DEBUG - 搜索请求 | 索引={index}, 查询={str(query)}, 限制={limit}")
        
        try:
            request_body = {
                "index": index,
                "limit": limit,
                "query": query
            }
            if options:
                request_body["options"] = options
            if sort:
                request_body["sort"] = sort

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
            # DEBUG: 打印原始响应
            logger.debug(f"DEBUG - 原始响应 | 状态码={resp.status_code}, 内容={resp.text[:200]}")
            return resp.status_code == 200
        except requests.exceptions.RequestException as e:
            # DEBUG: 捕获并打印完整异常
            logger.debug(f"DEBUG - 搜索异常 | 类型={type(e).__name__}, 错误={str(e)}")
            logger.debug(f"DEBUG - 异常堆栈:\n{traceback.format_exc()}")
            return False

    def _request(self, endpoint: str, index: str, id: int, doc: dict) -> bool:
        try:
            # 防御性检查：确保不包含 id 字段
            if "id" in doc:
                logger.error("⚠️ 非法操作：文档包含 id 字段（主键不可更新）")
                logger.error(f"文档内容: {json.dumps(doc, indent=2)}")
                doc = {k: v for k, v in doc.items() if k != "id"}
                
            # 收集调用栈信息
            from inspect import currentframe, getouterframes
            caller_info = []
            frames = getouterframes(currentframe())
            for frame in frames[1:6]:  # 获取最近的5层调用栈
                caller_info.append(f"{frame.filename}:{frame.lineno} ({frame.function})")
            
            # 添加防御性检查
            if 'j' in doc and doc['j'] is None:
                logger.error("检测到无效的 null j 字段，已自动清理")
                doc = {k: v for k, v in doc.items() if k != 'j'}

            url = f"{self.base_url}/{endpoint}"
            payload = {
                "index": index,
                "id": id,
                "doc": doc
            }
            
            logger.debug(f"DEBUG - 请求详情 | 端点: {endpoint}, URL: {url}")
            logger.debug(f"DEBUG - 请求负载: {json.dumps(payload, indent=2)}")
            
            resp = requests.post(
                url,
                json=payload,
                timeout=3
            )
            
            logger.debug(f"DEBUG - 响应状态: {resp.status_code}")
            logger.debug(f"DEBUG - 响应内容: {resp.text[:200]}")
            
            if resp.status_code != 200:
                # 详细错误日志
                logger.error(f"请求失败 | 状态码: {resp.status_code}")
                logger.error(f"请求端点: {endpoint}")
                logger.error(f"索引: {index}")
                logger.error(f"文档ID: {id}")
                logger.error(f"调用栈:\n{'\n'.join(caller_info)}")
                
                # 检查问题字段
                if 'j' in doc:
                    logger.error(f"字段 'j' 的值类型: {type(doc['j']).__name__}")
                    logger.error(f"字段 'j' 的内容片段: {str(doc['j'])[:100]}")
                else:
                    logger.error("文档中不存在 'j' 字段")
                
                logger.error(f"完整响应: {resp.text}")
            
            return resp.status_code == 200
        except requests.exceptions.RequestException as e:
            # 异常时的调用栈信息
            logger.error(f"请求异常 | 类型: {type(e).__name__}, 错误: {str(e)}")
            logger.error(f"调用栈:\n{'\n'.join(caller_info)}")
            logger.error(f"异常堆栈:\n{traceback.format_exc()}")
            return False
