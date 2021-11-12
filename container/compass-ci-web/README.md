# Compass CI web 前端服务

## 实现与启动
   1. 制作容器镜像
      node-alpine as a builder:       build crystal-ci(web) --> /compass-ci-web/dist
				           |		|
					   v      	|
		  nginx-alpine:	    	   |
					   |		|
					   |<-----------+
					   v
				      cp /compass-ci-web/dist from builder to $nginx_home
					   |
					   |
					   v
					ENTRYPOINT:
						nginx -g 'daemon off'

   2. 容器启动
      - start: 启动容器

      - ENV配置
        容器在启动前需要在配置文件中服务变量，这些服务变量会在容器启动前被设置为环境变量
	例如:
	```
	/etc/compass-ci/service/service-env.yaml:
		SRV_HTTP_PROTOCOL: https
		SRV_HTTP_RESULT_HOST: api.compass-ci.openeuler.org
		SRV_HTTP_RESULT_PORT: 20007

		WEB_BACKEND_PROTOCOL: https
		WEB_BACKEND_HOST: api.compass-ci.openeuler.org
		WEB_BACKEND_PORT: 20003 # 如果本地无ssl证书，那么这里port应设置为compass-ci/container/web-backend对应端口，默认为：10002
		...
	```
      - 运行命令
      ```
      cd compass-ci/container/srv-http
      ./build
      ./start
      ```


## 访问示例
   ```
   https://api.compass-ci.openeuler.org:20030
   ```

## 本地搭建compass-ci/container/compass-ci-web
   本地搭建时，会检查本地机器中/etc/ssl/certs/是否存在相应的ssl证书和密钥。如：
	```
	/etc/ssl/certs/web-backend.crt
	/etc/ssl/certs/web-backend.key
	```
   **如需前端服务支持https协议，可申请ssl证书密钥后，按照示例修改crt和key文件名称和路径**

   如果存在ssl证书和密钥，那么容器中的nginx将会添加ssl相应配置，支持https协议，访问方式如下：
	```
	https://<hostname>:<port
	如： https://localhost:20030
	```

   如不存在相应ssl证书和密钥，则容器默认之支持http协议，访问方式如下：
	```
	http://<hostname>:<port>/<filepath>
	如： http://localhost:20030
	```
