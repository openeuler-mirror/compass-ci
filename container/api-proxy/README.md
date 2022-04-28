# 背景
  实验室服务器不能直接通过互联网访问，因此需要一个代理服务部署在开放的服务器上，将互联网用户请求转发给实验室服务器。

# 实现
  使用nginx的`proxy_pass`功能转发用户请求给对应服务器的服务。
  配置`nginx.conf`即可，需要定义如下内容：
     - 开放哪些api/服务，支持用户通过互联网访问?
     - 每个开放服务对应的`proxy_pass`，即定义把请求转发给谁？

  nginx.conf eg:
  ```
  http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    include       /etc/nginx/conf.d/*.conf;
    server_tokens off;

    server {
		listen 9092;
                server_name api.compass-ci.openeuler.org;
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forward-For $proxy_add_x_forwarded_for;

                # proxy services hosts and port
		set $protocol https;

                set $crystal_host 123.60.114.27;
                set $z9_host 123.60.114.28;

                set $pub_host $z9_host;
                set $pub_port 20006;
		...


                # file servers
                location ~ ^/pub { # 根据用户请求的url中的路径，决定把用户请求转发给谁
                        proxy_pass $protocol://$pub_host:$pub_port;
                }
		...
            }
  ```
# 使用
## 服务部署
  将 `compass-ci/container/api-proxy`部署在一台开放的服务器上，如：
  ```
  api.compass-ci.openeuler.org
  ```
## 用户访问
  用户访问如下：
    ```
    https://api.compass-ci.openeuler.org/pub/
    ```
  `api-proxy` 按照nginx.conf配置转发请求至：
    ```
    https://123.60.114.27:20006/pub
    ```
  这样用户就可以访问实验室服务: `https://123.60.114.27:20006/pub/`

# 注意事项
  1. 代理服务器`proxy_pass` 也应采用`https` 协议，即实验室服务器部署对应服务时需要支持https访问。
     意味着服务器同样需要申请nginx-ssl证书，证书需要定期申请，一般每年需要申请一次。
  2. 服务器(z9, crystal) 公网ip变更时，需要同步修改`nginx.conf` 的 `$z9_host` | `$crystal_host`。
  3. 端口变更时，同理。
  4. 当前代理(api.compass-ci.openeuler.org)不支持高并发，允许并发量级：数千次 / 1s，当前满足用户访问web页面。
     testbox通过代理访问scheduler，访问文件服务器，会有风险
