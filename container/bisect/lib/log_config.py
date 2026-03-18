"""Central logging setup with structured log helpers for bisect components."""

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

_LOG_COMPONENT_CONTEXT = threading.local()


def set_log_component(component: str = None):
    """Set per-thread logical component for log routing.

    Args:
        component: one of {"producer", "consumer", "commit_time_service"}.
                   Pass None or empty string to clear.
    """
    if component:
        _LOG_COMPONENT_CONTEXT.component = component
    elif hasattr(_LOG_COMPONENT_CONTEXT, 'component'):
        delattr(_LOG_COMPONENT_CONTEXT, 'component')


def get_log_component() -> str:
    """Get current thread's routing component, or empty string if unset."""
    return getattr(_LOG_COMPONENT_CONTEXT, 'component', '')


def resolve_log_component(pathname: str = '', record_component: str = '') -> str:
    """Resolve effective component used by log handler routing."""
    if record_component:
        return record_component

    thread_component = get_log_component()
    if thread_component:
        return thread_component

    if '/services/commit_time_service/' in pathname or '\\services\\commit_time_service\\' in pathname:
        return 'commit_time_service'
    if 'bisect_producer' in pathname or 'producer_reporter' in pathname:
        return 'producer'
    return 'consumer'

class StructuredLogger:
    """log - support，"""

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
            
        # log
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
        
        # logconfig
        self.max_days = max_days
        self.log_dir = log_dir or self._get_default_log_dir()
        
        # log
        self.logger.setLevel(logging.DEBUG)  # Logger，

        self._setup_file_handlers(self.log_dir)
        self._setup_console_handler()
        
        # log
        self._cleanup_old_logs()
        
        self._initialized = True
        
        # initialize（file，）
        self._log_to_file_only('info', f"log | :{log_level_str} | :{max_days}")

    def _get_default_log_dir(self) -> str:
        """getdefaultlog"""
        #  RESULT_DIR/logs（）
        # ：RESULT_DIR  /result/bisect， bisect
        if os.getenv('RESULT_DIR'):
            base_dir = os.getenv('RESULT_DIR')
        elif os.getenv('WORK_DIR'):
            base_dir = os.getenv('WORK_DIR')
        else:
            base_dir = '/app' if os.path.exists('/app') else os.getcwd()

        log_dir = os.path.join(base_dir, 'logs')
        return os.path.abspath(log_dir)

    def _setup_file_handlers(self, log_dir: str):
        """Configure file handlers with per-component subdirectories.

        Directory structure:
          logs/consumer/   — consumer, validator, task_processor
          logs/producer/   — producer cycles, reporter
          logs/commit_time_service/ — commit-time HTTP service logs
          logs/performance/ — performance metrics
        API and commit-service logs are managed by supervisord.
        """
        log_path = Path(log_dir)

        # Create component subdirectories
        consumer_dir = log_path / 'consumer'
        producer_dir = log_path / 'producer'
        commit_time_service_dir = log_path / 'commit_time_service'
        consumer_dir.mkdir(parents=True, exist_ok=True)
        producer_dir.mkdir(parents=True, exist_ok=True)
        commit_time_service_dir.mkdir(parents=True, exist_ok=True)

        # Clear old handlers
        self.logger.handlers = []

        detailed_formatter = logging.Formatter(
            '%(asctime)s.%(msecs)03d [%(pathname)s:%(lineno)d] %(funcName)s() - %(message)s',
            '%Y-%m-%d %H:%M:%S'
        )

        # Component-aware filter: explicit record/thread component first, path fallback.
        class _ComponentFilter(logging.Filter):
            def __init__(self, component_name):
                super().__init__()
                self.component_name = component_name

            def filter(self, record):
                path = getattr(record, 'pathname', '')
                record_component = getattr(record, 'component', '')
                effective_component = resolve_log_component(path, record_component)
                record.component = effective_component
                return effective_component == self.component_name

        def _make_handler(filepath, level, component_filter=None):
            filepath.parent.mkdir(parents=True, exist_ok=True)
            h = TimedRotatingFileHandler(
                filename=filepath,
                when='D', interval=1,
                backupCount=self.max_days,
                encoding='utf-8'
            )
            h.suffix = '%Y-%m-%d'
            h.setFormatter(detailed_formatter)
            h.setLevel(level)
            if component_filter:
                h.addFilter(component_filter)
            return h

        # Producer logs
        producer_filter = _ComponentFilter('producer')
        self.logger.addHandler(_make_handler(producer_dir / 'producer.log', logging.INFO, producer_filter))
        self.logger.addHandler(_make_handler(producer_dir / 'error.log', logging.ERROR, producer_filter))

        # Commit-time service logs
        commit_time_service_filter = _ComponentFilter('commit_time_service')
        self.logger.addHandler(_make_handler(
            commit_time_service_dir / 'commit_time_service.log',
            logging.INFO,
            commit_time_service_filter
        ))
        self.logger.addHandler(_make_handler(
            commit_time_service_dir / 'error.log',
            logging.ERROR,
            commit_time_service_filter
        ))

        # Consumer logs (default bucket)
        consumer_filter = _ComponentFilter('consumer')
        self.logger.addHandler(_make_handler(consumer_dir / 'consumer.log', logging.INFO, consumer_filter))
        self.logger.addHandler(_make_handler(consumer_dir / 'error.log', logging.ERROR, consumer_filter))

    def _setup_console_handler(self):
        """config - file"""
        console = logging.StreamHandler()
        # filelog， supervisor 
        console_formatter = logging.Formatter(
            '%(asctime)s.%(msecs)03d [%(pathname)s:%(lineno)d] %(funcName)s() - %(message)s',
            '%Y-%m-%d %H:%M:%S'
        )
        console.setFormatter(console_formatter)
        # WARNING（）
        console.setLevel(logging.WARNING)
        self.logger.addHandler(console)

    def _cleanup_old_logs(self):
        """logfile"""
        try:
            log_path = Path(self.log_dir)
            if not log_path.exists():
                return
                
            cutoff_time = datetime.now() - timedelta(days=self.max_days)
            cleaned_count = 0
            
            for log_file in log_path.rglob('*.log*'):
                try:
                    file_time = datetime.fromtimestamp(log_file.stat().st_mtime)
                    if file_time < cutoff_time:
                        log_file.unlink()
                        cleaned_count += 1
                except Exception:
                    pass
                    
            if cleaned_count > 0:
                self._log_to_file_only('info', f" {cleaned_count} logfile")
                
        except Exception:
            pass

    def _log_to_file_only(self, level: str, message: str):
        """file，"""
        # 
        console_handlers = [h for h in self.logger.handlers if isinstance(h, logging.StreamHandler)]
        for h in console_handlers:
            self.logger.removeHandler(h)
        
        # log
        log_method = getattr(self.logger, level.lower())
        log_method(message)
        
        # 
        for h in console_handlers:
            self.logger.addHandler(h)

    def log_performance(self, operation: str, duration: float, **kwargs):
        """"""
        perf_data = {
            'operation': operation,
            'duration_ms': round(duration * 1000, 2),
            'session_id': self.session_id,
            **kwargs
        }
        perf_dir = Path(self.log_dir) / 'performance'
        perf_dir.mkdir(parents=True, exist_ok=True)
        perf_log_path = perf_dir / 'performance.log'
        try:
            with open(perf_log_path, 'a', encoding='utf-8') as f:
                f.write(f"{datetime.now():%Y-%m-%d %H:%M:%S} [PERF] {json.dumps(perf_data, ensure_ascii=False)}\n")
        except Exception:
            pass

    def debug(self, message: str, *args, **kwargs):
        #  logger 
        standard_kwargs = {}
        extra_kwargs = {}

        for key, value in kwargs.items():
            if key in ('exc_info', 'stack_info', 'stacklevel', 'extra'):
                standard_kwargs[key] = value
            else:
                extra_kwargs[key] = value

        # ， extra dict
        if extra_kwargs:
            standard_kwargs['extra'] = extra_kwargs

        if args:
            self.logger.debug(message, *args, stacklevel=2, **standard_kwargs)
        else:
            self.logger.debug(message, stacklevel=2, **standard_kwargs)

    def info(self, message: str, *args, **kwargs):
        #  logger 
        standard_kwargs = {}
        extra_kwargs = {}

        for key, value in kwargs.items():
            if key in ('exc_info', 'stack_info', 'stacklevel', 'extra'):
                standard_kwargs[key] = value
            else:
                extra_kwargs[key] = value

        # ， extra dict
        if extra_kwargs:
            standard_kwargs['extra'] = extra_kwargs

        if args:
            self.logger.info(message, *args, stacklevel=2, **standard_kwargs)
        else:
            self.logger.info(message, stacklevel=2, **standard_kwargs)

    def warning(self, message: str, *args, **kwargs):
        #  logger 
        standard_kwargs = {}
        extra_kwargs = {}

        for key, value in kwargs.items():
            if key in ('exc_info', 'stack_info', 'stacklevel', 'extra'):
                standard_kwargs[key] = value
            else:
                extra_kwargs[key] = value

        # ， extra dict
        if extra_kwargs:
            standard_kwargs['extra'] = extra_kwargs

        if args:
            self.logger.warning(message, *args, stacklevel=2, **standard_kwargs)
        else:
            self.logger.warning(message, stacklevel=2, **standard_kwargs)

    def error(self, message: str, *args, **kwargs):
        #  logger 
        standard_kwargs = {}
        extra_kwargs = {}

        for key, value in kwargs.items():
            if key in ('exc_info', 'stack_info', 'stacklevel', 'extra'):
                standard_kwargs[key] = value
            else:
                extra_kwargs[key] = value

        # ， extra dict
        if extra_kwargs:
            standard_kwargs['extra'] = extra_kwargs

        # Exception traceback（exception）
        import sys
        if sys.exc_info()[0] is not None and 'exc_info' not in standard_kwargs:
            standard_kwargs['exc_info'] = True

        if args:
            self.logger.error(message, *args, stacklevel=2, **standard_kwargs)
        else:
            self.logger.error(message, stacklevel=2, **standard_kwargs)

    def critical(self, message: str, *args, **kwargs):
        #  logger 
        standard_kwargs = {}
        extra_kwargs = {}

        for key, value in kwargs.items():
            if key in ('exc_info', 'stack_info', 'stacklevel', 'extra'):
                standard_kwargs[key] = value
            else:
                extra_kwargs[key] = value

        # ， extra dict
        if extra_kwargs:
            standard_kwargs['extra'] = extra_kwargs

        if args:
            self.logger.critical(message, *args, stacklevel=2, **standard_kwargs)
        else:
            self.logger.critical(message, stacklevel=2, **standard_kwargs)

    def exception(self, message: str, **kwargs):
        """exception，"""
        # supportkwargs，
        if 'error' in kwargs:
            message = f"{message}: {kwargs.pop('error')}"
        if 'exception' in kwargs:
            message = f"{message}: {kwargs.pop('exception')}"
        # 
        kwargs = {k: v for k, v in kwargs.items() if k in ['exc_info', 'stack_info']}

        # exception
        if 'exc_info' not in kwargs:
            kwargs['exc_info'] = True

        # exception（exception）
        import sys
        if sys.exc_info()[1]:
            exception_type = type(sys.exc_info()[1]).__name__
            message = f"{message} | Exception: {exception_type}"

        self.logger.error(message, stacklevel=2, **kwargs)
    
    def configure(self, log_dir: str = None, **kwargs):
        """config，py_bisect"""
        if log_dir:
            logger.debug(f"logconfig： {log_dir}")
            # configlog，
        return True
        
    def get_log_stats(self) -> Dict[str, Any]:
        """getlogstats"""
        stats = {
            'log_dir': self.log_dir,
            'session_id': self.session_id,
            'handlers_count': len(self.logger.handlers),
            'uptime_seconds': round(time.time() - self.start_time, 2)
        }
        
        # statslogfile
        try:
            log_path = Path(self.log_dir)
            if log_path.exists():
                total_size = sum(f.stat().st_size for f in log_path.rglob('*.log*'))
                file_count = len(list(log_path.rglob('*.log*')))
                stats.update({
                    'log_files_count': file_count,
                    'total_log_size_mb': round(total_size / 1024 / 1024, 2)
                })
        except Exception:
            pass
            
        return stats

# loginstance
logger = StructuredLogger()
