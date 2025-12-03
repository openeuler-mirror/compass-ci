import sys
import os
from flask import Flask

print(f"环境变量验证 - LOG_LEVEL = {os.getenv('LOG_LEVEL')}")

sys.path.append((os.environ['CCI_SRC']) + '/container/bisect/lib')
from log_config import logger
from config import Config

sys.path.append((os.environ['CCI_SRC']) + '/container/bisect/core')
from task_processor import bisect_task_instance

sys.path.append((os.environ['CCI_SRC']) + '/container/bisect/lib')
from repo_manager import SharedRepoManager

from .routes import api_bp

def create_app():
    app = Flask(__name__)

    # Load configuration from lib.config.Config
    app.config['PORT'] = Config.PORT
    app.config['MANTICORE_HOST'] = Config.MANTICORE_HOST
    app.config['MANTICORE_PORT'] = Config.MANTICORE_PORT
    app.config['BISECT_MODE'] = Config.BISECT_MODE

    # Initialize task processor and start background tasks

    # Ensure repository root directory exists
    repo_root = SharedRepoManager.REPO_BASE_DIR
    os.makedirs(repo_root, exist_ok=True)
    logger.info(f"Repository root directory created: {repo_root}")
    
    # Ensure initialization only once
    if not hasattr(bisect_task_instance, '_initialized'):
        logger.info("Forcing task processor initialization...")
        # Explicitly call initialization
        bisect_task_instance.__init__()
        # Validate repo_manager immediately after initialization
        if hasattr(bisect_task_instance, 'repo_manager'):
            logger.info("repo_manager initialized successfully")
            # Add additional validation logs
            logger.debug(f"Repository root: {bisect_task_instance.repo_manager.REPO_BASE_DIR}")
        else:
            logger.error("repo_manager not initialized")
            
        bisect_task_instance._initialized = True
        logger.info("Task processor initialization completed")

    # Delay starting background tasks to avoid duplicate starts in gunicorn workers
    bisect_task_instance._start_background_tasks()
    logger.info("Background tasks started")
    # Register blueprint
    app.register_blueprint(api_bp, url_prefix='/api/v1')
    
    return app
