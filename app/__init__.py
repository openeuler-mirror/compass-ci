from flask import Flask

def create_app():
    app = Flask(__name__)
    app.config.from_object('app.config.Config')
    
    # 注册蓝图
    from app.routes import api_bp
    app.register_blueprint(api_bp, url_prefix='/api/v1')
    
    return app
