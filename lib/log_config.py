# SPDX-License-Identifier: MulanPSL-2.0+

import logging
import os
import uuid
import time
from logging.handlers import RotatingFileHandler
from typing import Dict, Any
import json
import traceback
from datetime import datetime

class StructuredLogger:
    """统一的结构化日志记录器"""

    def __init__(self, log_dir: str = None, name: str = 'bisect-py'):

        self.logger = logging.getLogger(name)
        self.logger.propagate = False  # Prevent log propagation
        self.logger.handlers = []      # Clear existing handlers

        self.session_id = str(uuid.uuid4())[:8]
        self.start_time = time.time()
        self.context: Dict[str, Any] = {
            'session_id': self.session_id,
            'start_time': datetime.fromtimestamp(self.start_time).isoformat()
        }

        if log_dir:
            self._setup_file_handlers(log_dir)

        self._setup_console_handler()
        self._initialized = True

    def _setup_file_handlers(self, log_dir: str):
        """配置文件处理器"""
        os.makedirs(log_dir, exist_ok=True)

        # 合并为单个日志文件
        combined_handler = RotatingFileHandler(
            os.path.join(log_dir, 'bisect_process.log'),
            maxBytes=10*1024*1024,  # 10MB
            backupCount=5,
            encoding='utf-8'
        )

        # 统一日志格式
        formatter = logging.Formatter(
            '%(asctime)s.%(msecs)03d [%(levelname)s] %(pathname)s:%(lineno)d - %(message)s',
            '%Y-%m-%d %H:%M:%S'
        )
        combined_handler.setFormatter(formatter)
        combined_handler.setLevel(logging.DEBUG)

        # 清理旧handler后添加新handler
        self.logger.handlers = [
            h for h in self.logger.handlers
            if not isinstance(h, RotatingFileHandler)
        ]
        self.logger.addHandler(combined_handler)

    def _setup_console_handler(self):
        """配置控制台处理器"""
        console = logging.StreamHandler()
        console.setLevel(logging.INFO)
        console.setFormatter(logging.Formatter(
            '%(asctime)s - %(levelname)s - %(filename)s:%(lineno)d - %(message)s',
            '%Y-%m-%d %H:%M:%S'
        ))
        if not any(isinstance(h, logging.StreamHandler) for h in self.logger.handlers):
            self.logger.addHandler(console)
        self.logger.setLevel(logging.DEBUG)

    def configure(self, log_dir: str = None, level: int = logging.INFO):
        """动态配置日志"""
        if log_dir:
            self._setup_file_handlers(log_dir)
        self.logger.setLevel(level)

    def log(self, level: str, message: str, *args, **kwargs):
        """统一日志记录方法，支持格式化字符串和结构化日志"""
        log_entry = {
            'timestamp': datetime.now().isoformat(),
            'level': level.upper(),
            'message': message % args if args else message,
            **self.context,
            **kwargs
        }

        # 写入JSON日志
        json_handler = next(
            (h for h in self.logger.handlers
             if isinstance(h, RotatingFileHandler) and 'structured' in h.baseFilename),
            None
        )
        if json_handler:
            try:
                json_handler.stream.write(json.dumps(log_entry) + '\n')
            except Exception as e:
                pass

        # 调用标准日志方法，添加stacklevel参数以获取正确的调用位置
        log_method = getattr(self.logger, level)
        if args:
            log_method(message, *args, extra=kwargs, stacklevel=3)
        else:
            log_method(message, extra=kwargs, stacklevel=3)

    def debug(self, message: str, *args, **kwargs):
        self.log('debug', message, *args, **kwargs)

    def info(self, message: str, *args, **kwargs):
        self.log('info', message, *args, **kwargs)

    def warning(self, message: str, *args, **kwargs):
        self.log('warning', message, *args, **kwargs)

    def error(self, message: str, *args, **kwargs):
        self.log('error', message, *args, **kwargs)

    def exception(self, message: str, **kwargs):
        kwargs['exception'] = traceback.format_exc()
        self.log('error', message, **kwargs)

# 全局日志实例
logger = StructuredLogger()
