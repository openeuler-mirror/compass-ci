import sys
import os
from flask import Flask

sys.path.append((os.environ['CCI_SRC']) + '/src/bisect/lib')
from log_config import logger

sys.path.append((os.environ['CCI_SRC']) + '/src/bisect/app')
from task_processor import bisect_task_instance
from routes import api_bp

def create_app():
    app = Flask(__name__)
    app.config.from_object('app.config.Config')
    
    # 初始化任务处理器并启动后台任务
    
    # 延迟启动后台任务，避免在gunicorn worker中重复启动
    bisect_task_instance._start_background_tasks()
    logger.info("后台任务已启动")
    
    # 注册退出处理
    import atexit
    atexit.register(bisect_task_instance.cleanup)
    
    # 注册蓝图
    app.register_blueprint(api_bp, url_prefix='/api/v1')
    
    return app
