import sys
import os
import threading
import mysql.connector
sys.path.append((os.environ['LKP_SRC']) + '/programs/bisect-py/')
from log_config import logger

from typing import Optional, List, Dict, Any, Tuple
from mysql.connector import pooling, Error

class GenericSQLClient:
    """Generic SQL client base class providing connection pool and basic operations"""
 
    def __init__(
        self,
        host: str,
        port: str,
        database: str,
        pool_name: str = "generic_pool",
        pool_size: int = 5,
        autocommit: bool = True,
        readonly: bool = False
    ):
        self.host = host
        self.port = port
        self.database = database
        self.readonly = readonly
        self._connection_counter = 0  # 简单计数
        self.pool = None  # 显式初始化

        connect_args = {
            'host': host,
            'port': int(port),
            'database': database,
            'autocommit': autocommit,
            'connect_timeout': 10,
            'user': os.getenv('MYSQL_USER', 'root'),
            'password': os.getenv('MYSQL_PASSWORD', ''),
            'client_flags': [mysql.connector.ClientFlag.MULTI_STATEMENTS],
            'raise_on_warnings': True,
            'use_pure': True,
            'charset': 'utf8mb4',
            'collation': 'utf8mb4_unicode_ci',
            'pool_reset_session': False
        }

        try:
            self.pool = pooling.MySQLConnectionPool(
                pool_name=pool_name,
                pool_size=pool_size,
                **connect_args
            )
            logger.info(f"成功初始化连接池 {pool_name} ({pool_size} connections)")
        except RuntimeError as e:
            if "C Extension not available" in str(e):
                logger.warning("C 扩展不可用，切换至纯 Python 模式")
                connect_args['use_pure'] = True
                self.pool = pooling.MySQLConnectionPool(
                    pool_name=pool_name,
                    pool_size=pool_size,
                    **connect_args
                )
                logger.info(f"使用纯 Python 模式初始化连接池 {pool_name}")
        except Error as e:
            logger.error(f"连接池初始化失败: {str(e)}")
            raise RuntimeError(f"无法连接数据库 {database}@{host}:{port}")

    def get_connection(self):
        """进程安全的连接获取"""
        current_pid = os.getpid()
        if not hasattr(self, '_pool') or self.pid != current_pid:
            self._reinit_pool(current_pid)
        
        try:
            conn = self.pool.get_connection()
            self._connection_counter += 1
            logger.debug(f"获取连接 #{self._connection_counter}")
            return conn
        except AttributeError as e:
            logger.error("连接池未初始化，请检查以下配置：")
            logger.error(f"- 主机: {self.host}:{self.port}")
            logger.error(f"- 数据库: {self.database}")
            logger.error(f"- 连接池名称: {self.pool.pool_name}")
            raise RuntimeError("数据库连接池未正确初始化") from e
        except mysql.connector.PoolError as e:
            logger.error(f"获取连接失败 | 当前连接池状态：")
            logger.error(f"- 总连接数: {self.pool.pool_size}")
            logger.error(f"- 使用中连接: {self.pool._used_connections}")
            logger.error(f"- 最后错误: {str(e)}")
            raise

    def execute(
        self,
        sql: str,
        params: Optional[tuple] = None,
        operation: str = 'read'
    ) -> Optional[List[Dict]]:
        if self.readonly and operation != 'read':
            raise RuntimeError(f"Write operation forbidden on readonly database: {self.database}") 
        conn = self.pool.get_connection()
        try:
            with conn.cursor(dictionary=True) as cursor:
                cursor.execute(sql, params or ())

                if operation == 'read':
                    return cursor.fetchall()
                else:
                    conn.commit()
                    return cursor.rowcount

        except Error as e:
            logger.error(f"SQL operation failed: {e}")
            logger.error(f"Failed SQL: {sql}\nParams: {params}")
            conn.rollback()
            return None
        finally:
            try:
                if conn.is_connected():
                    conn.cmd_reset_connection()
            except Error:
                pass
            finally:
                conn.close()

    def health_check(self) -> bool:
        """连接池健康检查"""
        try:
            conn = self.pool.get_connection()
            conn.ping(reconnect=True)
            conn.close()
            return True
        except Error:
            return False

    def execute_transaction(
        self,
        queries: List[Tuple[str, tuple]]
    ) -> bool:
        """Execute transactional operations"""
        conn = self.pool.get_connection()
        try:
            conn.start_transaction()
            with conn.cursor() as cursor:
                for sql, params in queries:
                    cursor.execute(sql, params)
            conn.commit()
            return True
        except Error as e:
            conn.rollback()
            logger.error(f"Transaction failed: {e}")
            return False
        finally:
            conn.close()
