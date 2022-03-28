## 部署conserver之前的环境准备工作

1. 网络准备

conserver是调用ipmitool命令，通过服务器的管理网络(服务器带外管理网络)，收集服务器的串口日志。
实现了并发和日志存储。

所以，conserver容器需要能够访问服务器管理网络。
在下面的示例中，9.3.0.0是集群中服务器的管理网段。

```
~# docker exec -it conserver_server sh
/ # ping 9.3.3.5
PING 9.3.3.5 (9.3.3.5): 56 data bytes
64 bytes from 9.3.3.5: seq=0 ttl=63 time=0.250 ms

```

2. 配置文件准备

- conserver收集物理机串口日志需要用户名和密码

在容器启动脚本./start中，指定从"/etc/compass-ci/ipmi_info"文件中读取。
```
read -r user passwd <<< "$(< $ipmi_info)"
```

将物理机管理网段的用户名密码写入配置文件：
```
echo "<ipmi-user> <ipmi-passwd>" > /etc/compass-ci/ipmi_info"
chmod 640 /etc/compass-ci/ipmi_info"
```

- conserver收集物理机串口日志需要指定物理机管理ip

指定要收集的物理机ip列表信息保存在conserver.cf文件中

在容器构建脚本./build中，通过调用./generate_conserver.rb脚本去生成

详细过程见脚本。

