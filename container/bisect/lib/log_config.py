# SPDX-License-Identifier: MulanPSL-2.0+

import logging
import os
import uuid
import time
from logging.handlers import TimedRotatingFileHandler
from typing import Dict, Any
import json
import traceback
from datetime import datetime, timedelta
from pathlib import Path
import threading

class StructuredLogger:
    """统一的结构化日志记录器 - 支持按日期分割，减少控制台输出"""

    _instance = None
    _lock = threading.Lock()

    def __new__(cls, *args, **kwargs):
        if not cls._instance:
            with cls._lock:
                if not cls._instance:
                    cls._instance = super().__new__(cls)
        return cls._instance

    def __init__(self, log_dir: str = None, name: str = 'flask_bisect', max_days: int = 30):
        if hasattr(self, '_initialized'):
            return
            
        # 动态设置日志级别
        log_level_str = os.getenv('LOG_LEVEL', 'INFO').upper()
        self.log_level = getattr(logging, log_level_str, logging.INFO)
        
        self.logger = logging.getLogger(name)
        self.logger.propagate = False
        self.logger.handlers = []
        
        self.session_id = str(uuid.uuid4())[:8]
        self.start_time = time.time()
        self.context: Dict[str, Any] = {
            'session_id': self.session_id,
            'start_time': datetime.fromtimestamp(self.start_time).isoformat(),
            'pid': os.getpid()
        }
        
        # 日志清理配置
        self.max_days = max_days
        self.log_dir = log_dir or self._get_default_log_dir()
        
        # 设置全局日志级别
        self.logger.setLevel(logging.DEBUG)  # Logger本身接受所有级别，由处理器控制

        self._setup_file_handlers(self.log_dir)
        self._setup_console_handler()
        
        # 启动时清理旧日志
        self._cleanup_old_logs()
        
        self._initialized = True
        
        # 记录初始化信息（仅文件，不输出到控制台）
        self._log_to_file_only('info', f"日志系统已启动 | 级别:{log_level_str} | 保留:{max_days}天")

    def _get_default_log_dir(self) -> str:
        """获取默认日志目录"""
        if os.getenv('RESULT_DIR'):
            base_dir = os.getenv('RESULT_DIR')
        elif os.getenv('WORK_DIR'):
            base_dir = os.getenv('WORK_DIR')
        else:
            base_dir = '/app' if os.path.exists('/app') else os.getcwd()

        log_dir = os.path.join(base_dir, 'logs')
        return os.path.abspath(log_dir)

    def _setup_file_handlers(self, log_dir: str):
        """配置文件处理器"""
        log_path = Path(log_dir)
        log_path.mkdir(parents=True, exist_ok=True)

        # 清理旧的文件处理器
        self.logger.handlers = []

        # 通用格式化器 - 包含文件位置信息
        formatter = logging.Formatter(
            '%(asctime)s.%(msecs)03d [%(filename)s:%(lineno)d:%(funcName)s] %(message)s',
            '%Y-%m-%d %H:%M:%S'
        )

        # 错误日志专用格式化器 - 更详细的信息
        error_formatter = logging.Formatter(
            '%(asctime)s.%(msecs)03d [%(pathname)s:%(lineno)d] %(funcName)s() - %(message)s',
            '%Y-%m-%d %H:%M:%S'
        )

        # 1. 综合日志 (INFO及以上)
        all_handler = TimedRotatingFileHandler(
            filename=log_path / 'bisect_all.log',
            when='D',
            interval=1,
            backupCount=self.max_days,
            encoding='utf-8'
        )
        all_handler.suffix = '%Y-%m-%d'
        all_handler.setFormatter(formatter)
        all_handler.setLevel(logging.INFO)
        self.logger.addHandler(all_handler)

        # 2. 错误日志 (ERROR及以上) - 使用更详细的格式化器
        error_handler = TimedRotatingFileHandler(
            filename=log_path / 'bisect_error.log',
            when='D',
            interval=1,
            backupCount=self.max_days,
            encoding='utf-8'
        )
        error_handler.suffix = '%Y-%m-%d'
        error_handler.setLevel(logging.ERROR)
        error_handler.setFormatter(error_formatter)
        self.logger.addHandler(error_handler)

    def _setup_console_handler(self):
        """配置控制台处理器 - 仅显示重要信息，包含位置"""
        console = logging.StreamHandler()
        # 包含Flask标识和位置信息的格式
        console_formatter = logging.Formatter(
            '[flask] %(asctime)s [%(filename)s:%(lineno)d] %(message)s',
            '%H:%M:%S'
        )
        console.setFormatter(console_formatter)
        # 控制台显示WARNING及以上级别（重要信息）
        console.setLevel(logging.WARNING)
        self.logger.addHandler(console)

    def _cleanup_old_logs(self):
        """清理过期的日志文件"""
        try:
            log_path = Path(self.log_dir)
            if not log_path.exists():
                return
                
            cutoff_time = datetime.now() - timedelta(days=self.max_days)
            cleaned_count = 0
            
            for log_file in log_path.glob('*.log*'):
                try:
                    file_time = datetime.fromtimestamp(log_file.stat().st_mtime)
                    if file_time < cutoff_time:
                        log_file.unlink()
                        cleaned_count += 1
                except Exception:
                    pass
                    
            if cleaned_count > 0:
                self._log_to_file_only('info', f"清理了 {cleaned_count} 个过期日志文件")
                
        except Exception:
            pass

    def _log_to_file_only(self, level: str, message: str):
        """仅写入文件，不输出到控制台"""
        # 临时移除控制台处理器
        console_handlers = [h for h in self.logger.handlers if isinstance(h, logging.StreamHandler)]
        for h in console_handlers:
            self.logger.removeHandler(h)
        
        # 记录日志
        log_method = getattr(self.logger, level.lower())
        log_method(message)
        
        # 恢复控制台处理器
        for h in console_handlers:
            self.logger.addHandler(h)

    def log_performance(self, operation: str, duration: float, **kwargs):
        """记录性能信息"""
        perf_data = {
            'operation': operation,
            'duration_ms': round(duration * 1000, 2),
            'session_id': self.session_id,
            **kwargs
        }
        perf_log_path = Path(self.log_dir) / 'bisect_performance.log'
        try:
            with open(perf_log_path, 'a', encoding='utf-8') as f:
                f.write(f"{datetime.now():%Y-%m-%d %H:%M:%S} [PERF] {json.dumps(perf_data, ensure_ascii=False)}\n")
        except Exception:
            pass

    def debug(self, message: str, *args, **kwargs):
        # 分离标准 logger 关键字参数和额外的结构化参数
        standard_kwargs = {}
        extra_kwargs = {}

        for key, value in kwargs.items():
            if key in ('exc_info', 'stack_info', 'stacklevel', 'extra'):
                standard_kwargs[key] = value
            else:
                extra_kwargs[key] = value

        # 如果有额外参数，放入 extra 字典
        if extra_kwargs:
            standard_kwargs['extra'] = extra_kwargs

        if args:
            self.logger.debug(message, *args, stacklevel=2, **standard_kwargs)
        else:
            self.logger.debug(message, stacklevel=2, **standard_kwargs)

    def info(self, message: str, *args, **kwargs):
        # 分离标准 logger 关键字参数和额外的结构化参数
        standard_kwargs = {}
        extra_kwargs = {}

        for key, value in kwargs.items():
            if key in ('exc_info', 'stack_info', 'stacklevel', 'extra'):
                standard_kwargs[key] = value
            else:
                extra_kwargs[key] = value

        # 如果有额外参数，放入 extra 字典
        if extra_kwargs:
            standard_kwargs['extra'] = extra_kwargs

        if args:
            self.logger.info(message, *args, stacklevel=2, **standard_kwargs)
        else:
            self.logger.info(message, stacklevel=2, **standard_kwargs)

    def warning(self, message: str, *args, **kwargs):
        # 分离标准 logger 关键字参数和额外的结构化参数
        standard_kwargs = {}
        extra_kwargs = {}

        for key, value in kwargs.items():
            if key in ('exc_info', 'stack_info', 'stacklevel', 'extra'):
                standard_kwargs[key] = value
            else:
                extra_kwargs[key] = value

        # 如果有额外参数，放入 extra 字典
        if extra_kwargs:
            standard_kwargs['extra'] = extra_kwargs

        if args:
            self.logger.warning(message, *args, stacklevel=2, **standard_kwargs)
        else:
            self.logger.warning(message, stacklevel=2, **standard_kwargs)

    def error(self, message: str, *args, **kwargs):
        # 分离标准 logger 关键字参数和额外的结构化参数
        standard_kwargs = {}
        extra_kwargs = {}

        for key, value in kwargs.items():
            if key in ('exc_info', 'stack_info', 'stacklevel', 'extra'):
                standard_kwargs[key] = value
            else:
                extra_kwargs[key] = value

        # 如果有额外参数，放入 extra 字典
        if extra_kwargs:
            standard_kwargs['extra'] = extra_kwargs

        # 自动捕获异常堆栈（如果存在当前异常）
        import sys
        if sys.exc_info()[0] is not None and 'exc_info' not in standard_kwargs:
            standard_kwargs['exc_info'] = True

        if args:
            self.logger.error(message, *args, stacklevel=2, **standard_kwargs)
        else:
            self.logger.error(message, stacklevel=2, **standard_kwargs)

    def critical(self, message: str, *args, **kwargs):
        # 分离标准 logger 关键字参数和额外的结构化参数
        standard_kwargs = {}
        extra_kwargs = {}

        for key, value in kwargs.items():
            if key in ('exc_info', 'stack_info', 'stacklevel', 'extra'):
                standard_kwargs[key] = value
            else:
                extra_kwargs[key] = value

        # 如果有额外参数，放入 extra 字典
        if extra_kwargs:
            standard_kwargs['extra'] = extra_kwargs

        if args:
            self.logger.critical(message, *args, stacklevel=2, **standard_kwargs)
        else:
            self.logger.critical(message, stacklevel=2, **standard_kwargs)

    def exception(self, message: str, **kwargs):
        """记录异常信息，包含完整堆栈"""
        # 移除不支持的kwargs参数，只保留消息内容
        if 'error' in kwargs:
            message = f"{message}: {kwargs.pop('error')}"
        if 'exception' in kwargs:
            message = f"{message}: {kwargs.pop('exception')}"
        # 清理其他可能的无效参数
        kwargs = {k: v for k, v in kwargs.items() if k in ['exc_info', 'stack_info']}

        # 确保总是捕获异常信息
        if 'exc_info' not in kwargs:
            kwargs['exc_info'] = True

        # 记录异常类型（如果有当前异常）
        import sys
        if sys.exc_info()[1]:
            exception_type = type(sys.exc_info()[1]).__name__
            message = f"{message} | Exception: {exception_type}"

        self.logger.error(message, stacklevel=2, **kwargs)
    
    def configure(self, log_dir: str = None, **kwargs):
        """配置方法，为兼容py_bisect"""
        if log_dir:
            logger.debug(f"日志配置请求：设置目录为 {log_dir}")
            # 这里可以根据需要重新配置日志目录，暂时只记录
        return True
        
    def get_log_stats(self) -> Dict[str, Any]:
        """获取日志统计信息"""
        stats = {
            'log_dir': self.log_dir,
            'session_id': self.session_id,
            'handlers_count': len(self.logger.handlers),
            'uptime_seconds': round(time.time() - self.start_time, 2)
        }
        
        # 统计日志文件大小
        try:
            log_path = Path(self.log_dir)
            if log_path.exists():
                total_size = sum(f.stat().st_size for f in log_path.glob('*.log*'))
                file_count = len(list(log_path.glob('*.log*')))
                stats.update({
                    'log_files_count': file_count,
                    'total_log_size_mb': round(total_size / 1024 / 1024, 2)
                })
        except Exception:
            pass
            
        return stats

# 全局日志实例
logger = StructuredLogger()
