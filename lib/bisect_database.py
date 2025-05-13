#!/usr/bin/env python3
# SPDX-License-Identifier: MulanPSL-2.0+

from log_config import logger
import mysql.connector
from generic_sql_client import GenericSQLClient
from mysql.connector import Error
import json
from typing import Optional, Dict, Any, Tuple, List
from functools import wraps
import time
import threading
from manticore_simple import ManticoreClient

class BisectDB(GenericSQLClient):
    """Database operations for bisect process with connection pool"""

    def __init__(
        self,
        host: str,
        port: str,
        database: str,
        readonly: bool = False,
        pool_size: int = 5
    ):
        """Initialize database connection pool"""
        self._active_connections = threading.local()  # Thread local storage
        super().__init__(
            host=host,
            port=port,
            database=database,
            pool_name=f"{database}_pool",  # Isolate connection pools by database
            pool_size=pool_size,
            readonly=readonly
        )
        if not hasattr(self, '_cache'):
            self._cache = {}

    def execute_query(self, sql: str, params: Optional[tuple] = None) -> Optional[List[Dict]]:
        """Execute a SELECT query with connection pool (compatibility method)"""
        return self.execute(sql, params, operation='read')

    def execute_write(self, sql: str, params: Optional[tuple] = None) -> int:
        """Execute write operation with native parameter passing"""
        return super().execute(sql, params, operation='write')

    def execute_update(self, sql: str, params: Optional[tuple] = None) -> int:
        """Execute write operation with native parameter passing"""
        return super().execute(sql, params, operation='write')

    def execute_delete(self, sql: str, params: Optional[tuple] = None) -> int:
        """Execute write operation with native parameter passing"""
        return super().execute(sql, params, operation='write')


    def cache_query(ttl: int = 300):
        """Cache decorator for database queries"""
        def decorator(func):
            @wraps(func)
            def wrapper(self, *args, **kwargs):
                cache_key = f"{func.__module__}.{func.__name__}:" \
                           f"{hash(str(args))}:{hash(frozenset(kwargs.items()))}"
                if cache_key in self._cache:
                    timestamp, result = self._cache[cache_key]
                    if time.time() - timestamp < ttl:
                        return result
                result = func(self, *args, **kwargs)
                self._cache[cache_key] = (time.time(), result)
                return result
            return wrapper
        return decorator

    @cache_query(ttl=600)
    def get_job_info(self, job_id: str) -> Optional[Dict[str, Any]]:
        """
        Fetch job information from database

        Args:
            job_id: The job ID to fetch

        Returns:
            Dict containing job information or None if not found
        """
        try:
            # Ensure job_id is valid integer
            try:
                job_id_int = int(job_id)
            except ValueError:
                logger.error(f"Invalid job ID format: {job_id}")
                return None

            connection = self.get_connection()
            cursor = connection.cursor(dictionary=True)

            query = "SELECT j FROM jobs WHERE id = %s LIMIT 1"
            cursor.execute(query, (int(job_id),))
            result = cursor.fetchone()

            if not result or 'j' not in result:
                return None

            return (json.loads(result['j'])
                   if isinstance(result['j'], str)
                   else result['j'])

        except Error as e:
            logger.error(f"Database error: {e}")
            return None
        finally:
            if cursor:
                cursor.close()

    @cache_query(ttl=600)
    def check_existing_job(self, job: Dict[str, Any], limit: int = 1) -> List[Tuple[str, str]]:
        """
        Check if jobs with same configuration exist

        Args:
            job: Job configuration to check
            limit: Maximum number of results to return

        Returns:
            List of (job_id, result_root) tuples, empty list if none found
        """
        try:
            connection = self.get_connection()
            cursor = connection.cursor(dictionary=True)

            # Keep only core query conditions
            conditions = []
            if 'program' in job:
                for path, value in self._flatten_dict(job['program'], 'program'):
                    conditions.append(f"j.{path} = {self._format_sql_value(value)}")

            if job.get('ss'):
                for path, value in self._flatten_dict(job['ss'], 'ss'):
                    conditions.append(f"j.{path} = {self._format_sql_value(value)}")

            where_clause = " AND ".join(conditions) if conditions else "1=1"

            # Simplified query
            query = f"""
                SELECT id, j.result_root as result_root
                FROM jobs
                WHERE {where_clause}
                AND j.stats IS NOT NULL
                ORDER BY submit_time DESC
                LIMIT {limit}
            """

            cursor.execute(query)
            results = cursor.fetchall()

            return [(result['id'], result['result_root']) for result in results] if results else []

        except Error as e:
            logger.error(f"Database error: {e}")
            return None
        finally:
            if cursor:
                cursor.close()

    def _flatten_dict(self, d: Dict, prefix: str = '') -> list:
        """Flatten nested dictionary into (path, value) pairs"""
        items = []
        for k, v in d.items():
            key_path = f"{prefix}.{k}" if prefix else k
            if isinstance(v, dict):
                items.extend(self._flatten_dict(v, key_path))
            else:
                items.append((key_path, v))
        return items

    def _format_sql_value(self, value):
        """安全格式化 SQL 值（避免反斜杠和语法错误）"""
        if isinstance(value, (int, float)):
            return str(value)
        elif isinstance(value, str):
            # 先转义单引号，再包裹外层引号
            escaped = value.replace("'", "''")
            return f"'{escaped}'"
        else:
            # 处理非字符串类型（如字典、列表）
            json_str = json.dumps(value).replace("'", "''")
            return f"'{json_str}'"

    def close(self):
        """安全关闭连接池"""
        try:
            if hasattr(self, 'pool'):
                self.pool.close()
                logger.info(f"已关闭 {self.database} 数据库连接池")
                # 防止重复关闭
                del self.pool
        except Exception as e:
            logger.error(f"关闭数据库连接池失败: {str(e)}")

    def check_connection_leaks(self):
        """增强泄漏检查"""
        try:
            if hasattr(self._active_connections, 'count') and self._active_connections.count > 0:
                logger.error(f"⚠️ 检测到连接泄漏！当前未释放连接数: {self._active_connections.count}")
                self._active_connections.count = 0
        except AttributeError:
            pass

    def get_pool_status(self) -> dict:
        """获取连接池状态（兼容 Manticore）"""
        try:
            return {
                "database": self.database,
                "pool_size": self.pool.pool_size,
                "in_use": [conn.is_connected() for conn in self.pool._connections],
                "idle": self.pool._cnx_queue.qsize(),
                "total": self.pool.pool_size,
                "available": self.pool.pool_size - self.pool._used_connections
            }
        except Exception as e:
            logger.error(f"获取连接池状态失败: {str(e)}")
            return {"error": str(e)}
