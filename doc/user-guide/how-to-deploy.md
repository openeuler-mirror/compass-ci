# 部署compass-ci

## 前置说明
需提前规划并在相关节点上部署k8s集群，本文介绍为在现有k8s集群上自动化部署compass-ci。

## 自动化部署
auto-deploy文件夹说明：
- **0-cci-deploy**: 在compass-ci管理面节点上部署组件


## 一、参数及物料准备

0-cci-deploy涉及的部署文件位于`manifests`目录下，本节默认操作根目录为`manifests`。其中，原始配置在`_conf`下，其最终生成目录结构如下：

```shell
├── es-cert
│   └──elastic-certificates.p12
├── secret-service.env
```

修改`_conf/secret-service.env`

```toml
ES_SUPER_USER=root      # 固定
ES_SUPER_PASSWORD=""    # 自动生成，无需填写
ES_ROLE=biz-role        # 固定
ES_USER=biz-user        # 固定
ES_PASSWORD=""          # 自动生成，无需填写
ETCD_USER=root          # 固定
ETCD_PASSWORD=""        # 自动生成，无需填写
```

### 配置完所有信息，运行

生成kubernetes配置文件
prepare 需要两个参数 MASTER_IP MASTER_INTERFACE
MASTER_IP: 是宿主机的ip，和其他执行机相互连通的ip，如172.168.x.x
MASTER_INTERFACE: 是配置MASTER_IP所在的网卡，如enp125s0f0
可使用ifconfig命令查询，命令输出结果如下
...
enp125s0f0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
        inet 172.168.x.x  netmask 255.255.0.0  broadcast 172.168.255.255
...
> 注意执行prepare脚本时，需要配置成自己环境的ip和网卡！！！
```shell
./prepare 172.168.x.x enp125s0f0
```

## 二、镜像包准备

在联网环境的openEuler机器上执行0-cci-deploy目录下的build脚本，提前下载安装所需的物料。build脚本**依赖python3，tar，docker(version>20.xx)**。

```shell
cd auto-deploy/0-cci-deploy

./build

```

## 三、执行部署

将compass-ci目录拷贝到部署环境的某一台节点上，并以该节点作为部署节点（推荐：选择一台节点作为k8s master节点，并以该节点作为部署节点）。

### hosts-all.ini 配置文件说明

| 参数 | 说明 |
| --- | --- |
| ansible_ssh_host | host IP（如果是云环境，不要填写EIP） |
| ansible_port | ssh端口 |
| ansible_user | ssh用户名 |
| ansible_ssh_pass | ssh密码 |
| architecture | 架构，amd64或arm64 |
| oeversion | openEuler版本，`22.03-LTS`或`24.03-LTS`（若22.03-LTS-SPx版本，则填写22.03-LTS）|
| runtime | docker或containerd（执行机的runtime必须为docker）|

执行自动化部署命令

```shell
cd auto-deploy/0-cci-deploy

# 修改hosts.ini内容，配置compass-ci部署参数
vi hosts.ini

# 测试节点连接，确保所有节点可访问
export ANSIBLE_HOST_KEY_CHECKING=False
ansible all -m ping -i hosts.ini

# 运行deploy-cci playbook，安装compass-ci服务
ansible-playbook -i ../hosts-all.ini -i hosts.ini -e @variables.yml deploy-cci.yml
```
