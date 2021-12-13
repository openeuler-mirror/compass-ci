# 本地搭建 Compass-CI（简称CCI）集群

目前Compass-CI支持两种本地搭建模式，第一种是最小环境安装[本地Compass-CI节点](https://gitee.com/wu_fengguang/compass-ci/blob/master/sparrow/README.md)（只需一台虚拟机），第二种是本地搭建Compass-CI集群（需要一台物理机作为服务端，一台或多台物理机作为物理测试机）。

在 openEuler 系统搭建Compass-CI集群，该集群需要使用一台物理机作为服务端，另外一台或多台物理机作为测试机用于执行任务,
本文以两台物理机搭建compass-ci集群为例。后续想要扩大集群规模，只需重复执行添加测试机步骤即可。

注意：
compass-ci集群搭建过程中，需要在本地运行dnsmasq服务，同一个局域网内运行两个dnsmasq服务将影响compass-ci集群正常运行,
使用br0（支持自定义网段，不指定默认使用172.18网段），请检查您当前网络环境规划是否与本集群所使用的网络配置冲突，如果
有冲突，请重新规划网络配置。

## 环境准备

## 开始搭建
请使用root用户开始搭建。
- 设置文件权限
```bash
umask 002
```
注意：
umask 002 只是暂时设置umask值，需要修改/etc/bashrc中的umask值为002才能长期有效。
执行下个步骤前请确保当前umask值为002，否则因文件权限问题将导致部分服务无法正常运行。

- 创建工作目录并克隆 compass-ci 项目代码
```bash
mkdir -p /c/
git clone https://gitee.com/wu_fengguang/compass-ci.git /c/compass-ci
```

- 编辑setup.yaml
```bash
vi /c/compass-ci/sparrow/setup.yaml
```
请根据如下说明填写setup.yaml文件，集群部署过程中将首先copy该文件到/etc/compass-ci/setup.yaml，方便部署过程中读取该配置。

lab（必填）： 需要自定义一个本地git仓库的名称，我们官方Compass-CI集群正在使用的是[z9](https://gitee.com/wu_fengguang/lab-z9.git)，当本地部署Compass-CI集群时，将在本地/c目录下创建一个新的名为lab-$lab的git仓库，用于后续步骤添加测试机。

my_account, my_name, my_email（必填）：请为root用户填写帐号，用户名，邮箱，用于注册本地搭建compass-ci集群帐号，
注册帐号后才能通过校验，成功向本地搭建的compass-ci提交测试任务，否则提交任务失败，报错如下所示：
root@taishan200-2280-2s64p-256g--a1001 ~# submit host-info.yaml
submit_id=b0994b81-08f0-4bc4-999e-7220b85e280b
submit /c/lkp-tests/jobs/host-info.yaml failed, got job id=0, error: Missing required job key: 'my_token'.
Please refer to https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/account/apply-account.md
帐号注册成功之后，帐号信息会被存储在es数据库中，并在本地目录生成对应的yaml文件：
~/.config/compass-ci/defaults/account.yaml
~/.config/compass-ci/include/lab/$lab.yaml

注意：
该文档中提到的注册帐号是向本地搭建的compass-ci集群注册帐号，与官方的compass-ci帐号注册没有关系，只需填写您的常用邮箱地址，
并自定义一个用户名和帐号即可，下文中提到的非root用户注册帐号同理。

interface（必填）, dhcp-range（必填）： [配置dnsmasq服务](http://www.thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html)，以便执行测试任务时为测试机分发ip地址。
interface为compass-ci集群服务端的内网ip地址对应的网卡名称。
dhcp-range为dhcp分配的地址范围，建议该范围要大于测试机的数量，租期建议设置久一些（建议设置1440h）。
dnsmasq服务配置将被用于在本地目录生成对应的conf文件，此处的$lab就是上文中提到的自定义的lab名称：
/c/compass-ci/container/dnsmasq/dnsmasq.d/$lab.conf

br0_segment（选填）： br0网段前两位，默认值为172.18，如果当前环境中的172.18网段未被占用可不填。

setup.yaml中的其他配置项与compass-ci集群搭建无关，请忽略。
按照如上所述修改好配置文件后保存退出文本即可。

**说明：**
请注意yaml文件格式，冒号后面必须有一个空格。

- 执行部署集群脚本 install-cluster
```bash
cd /c/compass-ci/sparrow && ./install-cluster
```

install-cluster脚本大概需要运行一个小时，主要耗时在将数十个dockerfile文件构建成微服务镜像并运行在服务端。
调用了脚本/c/compass-ci/sparrow/4-docker/buildall，/c/compass-ci/container目录下就是所有微服务，例如rabbitmq，
redis，es，scheduler等，请耐心等待脚本执行结束。

## 环境测试
本文以/c/lkp-tests/jobs/目录下已有的测试用例host-info.yaml为例，用来检测当前部署的集群环境是否正常，该host-info.yaml是用来测试测试机的cpu，内存，硬盘等信息的，
详情见测试脚本/c/lkp-tests/tests/host-info。
- 使环境变量生效
```bash
source /etc/profile.d/compass.sh
```

- 使用[submit命令](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/job/submit/submit-job.zh.md)提交测试用例
```bash
submit host-info.yaml
```

执行上述命令会打印提示信息如下:
```
submit_id=bf5e7ad7-839d-48ec-a033-23281323c750
submit /c/lkp-tests/jobs/host-info.yaml, got job id=$lab.1
```

- 查看任务结果
等待约1分钟，可根据上一步骤中打印的job id查看任务结果(请将下行命令中的$lab.1替换为上一步骤中打印出的job id)。
```bash
cd $(es-find id=$lab.1 |grep result_root|awk -F '"' '{print "/srv/"$4}') && ls
```

结果文件介绍
job.yaml文件
job.yaml 文件中部分字段是用户提交上来的，其他字段是平台根据提交的 job 自动添加进来的。此文件包含了测试任务需要的所有参数。

output文件
output 文件记录了用例的执行过程，文件最后部分一般会有 check_exit_code 这个状态码，非 0 代表测试用例错误。

stats.json
测试用例执行完成会生成一个与测试用例同名的文件，记录它们的测试命令及标准化输出结果。compass-ci 会对这些文件进行解析，生成后缀名是 .json 的文件。
stats.json 是所有的 json 文件的汇总，所有测试命令的关键结果都会统计到这个文件中，便于后续的比较和分析。

Compass-CI服务端搭建完毕。

常见问题汇总，请按需阅读以下文档。

- 增加rootfs
启动测试机需要使用我们自制的rootfs文件，集群部署脚本install-cluster会自动准备好一个openeuler（系统版本为openeuler/aarch64/20.03）的rootfs文件，
如果需要使用其他os版本，请使用该脚本/c/compass-ci/sbin/download-rootfs下载，用法见脚本内注释。

- 非root用户注册账号
注册帐号需要将帐号信息写入es数据库，只有在微服务es运行的状态下才能注册成功，可使用'docker ps  | grep es-server01'检查该容器是否在up状态。
非root用户也需要注册帐号才能提交任务，该用户登录系统后直接使用build-my-info命令注册（该命令已添加到PATH环境变量中，直接执行即可）

```bash
build-my-info -e $my_email -n $my_name -a $my_account
```
例如给用户张三注册帐号：
```bash
build-my-info -e zhangsan@example.com -n zhangsan -a zs
```
更多build-my-info命令的用法，可使用"build-my-info --help" 进行查看

- [自动化测试](https://gitee.com/wu_fengguang/compass-ci/blob/master/sparrow/local/test-oss-project.md)
将待测试仓库地址、测试用例、测试脚本放在指定目录下，当待测试仓库有新的patch合入时，会自动触发测试。
