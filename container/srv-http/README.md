# srv-http 文件服务器
## 背景
   compass-ci需要共享一些文件供用户浏览和下载，如：
     测试结果，os, initrd, rpm等。

## 实现与启动
   1. 制作容器镜像
      node-alpine as a builder:       build h5ai --> /h5ai
				           |		|
					   v      	|
		  nginx-alpine:	      install php-7	|
					   |		|
					   |<-----------+
					   v
				      cp /h5ai from builder to $nginx_home
					   |
					   |
					   v
					ENTRYPOINT:
						nginx
						/usr/sbin/php-fpm7

	由于h5ai组件会使访问时产生更多的请求（约20倍），为减轻代理服务器(api.compass-ci.openeuler.org)压力，已移除h5ai对应功能。
	如仍要使用，可将代码回退到如下版本，再部署
		git reset --hard 2456074d824a875fde7a5d4ea678ffcf842fa0f8

   2. 容器启动
      - 容器有如下启动脚本：
        start start-cci  start-git  start-initrd  start-os  start-pub  start-result  start-rpm
	start: 启动所有start-*的容器
	单独运行某个start-*，则可以单独启动对应的容器

      - ENV配置
        每个容器在启动前需要在环境变量中声明对应的SRV_HTTP_*_HOST, SRV_HTTP_*_PORT,
	例如:
	```
	/etc/compass-ci/service/service-env.yaml:
		SRV_HTTP_RESULT_HOST: api.compass-ci.openeuler.org
		SRV_HTTP_OS_HOST: api.compass-ci.openeuler.org
		SRV_HTTP_GIT_HOST: api.compass-ci.openeuler.org
		SRV_HTTP_CCI_HOST: api.compass-ci.openeuler.org
		...
		SRV_HTTP_RESULT_PORT: 20007
		SRV_HTTP_OS_PORT: 20009
		SRV_HTTP_GIT_PORT: 20010
		SRV_HTTP_CCI_PORT: 20011
		...
	```
      - 运行命令
      ```
      cd compass-ci/container/srv-http
      ./build
      ./start
      ```

   3. https 启动
      文件服务器对互联网用户提供服务，安全起见，文件服务器支持https访问。需要主机ip申请ssl证书, 并放置到如下位置
          `/etc/ssl/certs/web-backend.key`
          `/etc/ssl/certs/web-backend.crt`

      容器启动：
	```
	有ssl证书文件
		|
		v
	./docker_run.sh: -v /etc/ssl/certs:/opt/cert
		|
		v
	./root/sbin/entrypoint.sh:
	   设置nginx.conf:
	       listen $port ssl
	       https 启动设置
	   启动nginx
	```

## 访问示例
   ```
   https://api.compass-ci.openeuler.org:20007/result/
   ```

## 本地搭建compass-ci/container/srv-http
   本地搭建时，会检查本地机器中/etc/ssl/certs/是否存在相应的ssl证书和密钥。如：
	```
	/etc/ssl/certs/web-backend.crt
	/etc/ssl/certs/web-backend.key
	```
   **如需要文件服务器支持https协议，可申请ssl证书密钥后，按照示例修改crt和key文件名称和路径**

   如果存在ssl证书和密钥，那么容器中的nginx将会添加ssl相应配置，支持https协议，访问方式如下：
	```
	https://<hostname>:<port>/<filepath>
	如： https://localhost:20007/result/
	```

   如不存在相应ssl证书和密钥，则容器默认之支持http协议，访问方式如下：
	```
	http://<hostname>:<port>/<filepath>
	如： http://localhost:20007/result/
	```
