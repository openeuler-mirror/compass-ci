#!/usr/bin/env python3
import threading
from concurrent.futures import ThreadPoolExecutor
from app import create_app
from app.task_processor import bisect_task_instance
from lib.log_config import logger

def main():
    app = create_app()
    executor = ThreadPoolExecutor(max_workers=3)
    
    # 启动后台线程
    executor.submit(bisect_task_instance.bisect_producer)
    executor.submit(bisect_task_instance.bisect_consumer)
    
    # 启动Flask应用
    app.run(host='0.0.0.0', port=app.config['PORT'])

if __name__ == "__main__":
    main()
