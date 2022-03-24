# 本地搭建 Compass-CI（简称CCI）集群

目前Compass-CI支持两种本地搭建模式，第一种是最小环境安装[本地Compass-CI节点](https://gitee.com/wu_fengguang/compass-ci/blob/master/sparrow/README.md)（只需一台虚拟机），第二种是本地搭建Compass-CI集群（需要一台物理机作为服务端，一台或多台物理机作为物理测试机）。

在 openEuler 系统搭建Compass-CI集群，该集群需要使用一台物理机作为服务端，另外一台或多台物理机作为测试机用于执行任务,
本文以两台物理机搭建compass-ci集群为例。后续想要扩大集群规模，只需重复执行[添加测试机步骤](https://gitee.com/wu_fengguang/compass-ci/blob/master/sparrow/local/add_testbox_to_cci_cluster.zh.md)。

注意：
compass-ci集群搭建过程中，需要在本地运行dnsmasq服务，同一个局域网内运行两个dnsmasq服务将影响compass-ci集群正常运行,
使用br0（支持自定义网段，不指定默认使用172.18网段），请检查您当前网络环境规划是否与本集群所使用的网络配置冲突，如果
有冲突，请重新规划网络配置。

## 环境准备
>**说明：**
>本文只适用于在较为干净的openEuler系统一键部署CCI环境，如果您的环境中有如下设置，将无法成功部署：
>1.lkp用户UID不是1090（如果没有该用户请忽略）
>2.运行了Kubernetes（CCI需要使用docker，而非podman-docker，且CCI需要占用很多服务端口，例如es， redis， rabbitmq等，易与当前环境中已使用的端口冲突）

### 硬件要求
        服务器类型：ThaiShan200-2280 (建议)
        架构：aarch64（支持x86架构，可能会遇到问题，欢迎向我们报告或fix bug）
        内存：>= 32GB
        CPU：64 nuclear (建议)
        硬盘：>= 500G

### 软件要求
        OS：openEuler-aarch64-20.03 LTS（支持centos/debian，可能会遇到问题，欢迎向我们报告或fix bug）

        git：2.2 (we are using this version)
        docker: 18.09 (we are using this version)
        网络：可以访问互联网(本文中所使用的openeuler系统防火墙开启或关闭均可正常部署，其他系统有风险，如果部署出现网络问题，请检查防火墙)

        >**说明：**
        >[openEuler 系统安装](https://openeuler.org/zh/docs/20.03_LTS/docs/Installation/%E5%AE%89%E8%A3%85%E5%87%86%E5%A4%87.html)

#### [划分独立分区](https://gitee.com/wu_fengguang/compass-ci/blob/master/sparrow/local/create_partition.md)
##### /srv
承载了CCI的数据存储，是CCI数据服务的根目录。
```
/srv
├── cache
├── cci
├── es
├── etcd
├── git
├── initrd
├── os
├── pub
├── rabbitmq
├── redis
├── result
├── rpm
├── tmp
└── upload-files
```

##### /srv/result
每个 Job 的结果保存路径，建议划分独立分区，定期清理。

以CCI官方服务器上的job结果空间使用情况为例
较小的job结果所占的空间：
```
du -sh /srv/result/host-info/2021-12-23/vm-2p8g/openeuler-20.03-aarch64/z9.13207965
1.2M    /srv/result/host-info/2021-12-23/vm-2p8g/openeuler-20.03-aarch64/z9.13207965
```

较大的job结果所占用的空间：
```
du -sh /srv/result/multi-qemu-docker/2021-10-08/taishan200-2280-2s48p-256g--a25/openeuler-
20.03-aarch64/6-ext4-raid0-10-dc-1g-10-dc-2g-10-dc-4g-20-dc-8g-10/z9.11023894
470M    /srv/result/multi-qemu-docker/2021-10-08/taishan200-2280-2s48p-256g--a25/openeuler
-20.03-aarch64/6-ext4-raid0-10-dc-1g-10-dc-2g-10-dc-4g-20-dc-8g-10/z9.11023894
```

所以建议该目录独立划分200G的空间，建议使用LVM，方便后续动态扩容。

###### /srv/result 定期清理脚本(待补充)

##### /var/lib/docker
以CCI官方服务器上的/var/lib/docker空间使用情况为例
```
df -h /var/lib/docker
Filesystem                     Size  Used Avail Use% Mounted on
/dev/mapper/vg--os-lv--docker  1.1T  480G  573G  46% /var/lib/docker
```

CCI所有的微服务的安装目录，建议划200G分独立分区，建议使用LVM，方便后续动态扩容。

## 开始搭建
请使用root用户开始搭建。
- 设置文件权限
```bash
umask 002
```
注意：
umask 002 只是暂时设置umask值，需要修改/etc/bashrc中的umask值为002才能长期有效。
执行下个步骤前请确保当前umask值为002，否则因文件权限问题将导致部分服务无法正常运行。

- 创建工作目录并克隆compass-ci和lkp-tests项目代码，并使用指定的commit id
```bash
mkdir -p /c/
yum install -y git
git clone https://gitee.com/wu_fengguang/compass-ci.git /c/compass-ci
git clone https://gitee.com/wu_fengguang/lkp-tests.git /c/lkp-tests
cd /c/compass-ci
git reset --hard 0b0a132469d9ba2a624ef36a136b7b47c6626eab
cd /c/lkp-tests
git reset --hard 54653df2ca76b6382ecf5990e857deacdead1497
```

>**说明：**
>该版本已经过验证，可以正常进行部署。
- 编辑setup.yaml
```bash
vi /c/compass-ci/sparrow/setup.yaml
```
>**说明：**
>请根据如下说明填写setup.yaml文件，在下个步骤执行部署集群脚本脚本install-cluster中，将自动copy该文件到/etc/compass-ci/setup.yaml，方便部署过程中读取该配置。
>请注意yaml文件格式，冒号后面必须有一个空格。
>          
>my_account, my_name, my_email（必填）：用于注册本地搭建compass-ci集群帐号，请自定义一个帐号和用户名，邮箱只需填写您的常用邮箱地址即可。该文档中提到的注册帐号是向本地搭建的compass-ci集群注册帐号，与官方的compass-ci帐号注册没有关系。当执行部署脚本install-cluster时，自动将root用户的帐号信息存储在es数据库中，并在本地目录生成对应的yaml文件，无需手动创建。            
>```      
>~/.config/compass-ci/defaults/account.yaml      
>~/.config/compass-ci/include/lab/$lab.yaml（此处的$lab就是上文中提到的自定义的lab名称）        
>```      
>lab（必填）： 需要自定义一个本地git仓库的名称，我们官方Compass-CI集群自定义的本地仓库名称为[z9](https://gitee.com/wu_fengguang/lab-z9.git)，当执行部署脚本install-cluster时，将自动在本地/c目录下初始化一个新的名为lab-$lab的git仓库并克隆下来，用于后续步骤添加测试机，无需手动创建。         
>```
>/c/lab-$lab.git            
>/c/lab-$lab          
>```    
>interface（必填）, dhcp-range（必填）： [配置dnsmasq服务](http://www.thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html)，以便执行测试任务时为测试机分发ip地址。interface为compass-ci集群服务端的内网ip地址对应的网卡名称,例如您的内网ip地址为172.168.xx.xx，网卡名称可使用如下命令获取:          
>```
>ip addr | grep 172.168 | awk '{print $NF}'        
>```
>dhcp-range为dhcp为物理测试机分配的ip地址范围和租期，建议该范围要大于测试机的数量且要与服务端的内网ip地址，当执行部署脚本install-cluster时，将读取dnsmasq配置并自动在本地目录生成对应的conf文件，无需手动创建。          
>```
>/c/compass-ci/container/dnsmasq/dnsmasq.d/$lab.conf（此处的$lab就是上文中提到的自定义的lab名称）          
>```
>br0_segment（选填）： br0网段前两位，默认值为172.18，如果当前环境中的172.18网段未被占用可不填。          
>
>setup.yaml中的其他配置项与compass-ci集群搭建无关，请忽略。按照如上所述修改好配置文件setup.yaml后保存退出文本即可。          

- 执行部署集群脚本 install-cluster
```bash
cd /c/compass-ci/sparrow && ./install-cluster
```

install-cluster脚本大概需要运行一个小时，主要耗时在将数十个dockerfile文件构建成微服务镜像并运行在服务端。          
调用了脚本/c/compass-ci/sparrow/4-docker/buildall，/c/compass-ci/container目录下就是所有微服务，例如rabbitmq，          
redis，es，scheduler等，请耐心等待脚本执行结束。          

- 重启dnsmasq服务
为了使dnsmasq配置生效，需要重启dnsmasq，容器微服务的重启均由container目录下各个微服务对应的start脚本完成。
```bash
cd /c/compass-ci/container/dnsmasq
./start
```

## 环境测试
本文以/c/lkp-tests/jobs/目录下已有的测试用例host-info.yaml为例，用来检测当前部署的集群环境是否正常，该host-info.yaml是用来测试测试机的cpu，内存，硬盘等信息的，
详情见测试脚本/c/lkp-tests/tests/host-info。
- 使环境变量生效
```bash
source /etc/profile.d/compass.sh
```

- 使用[submit命令](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/job/submit/submit-job.zh.md)提交测试用例
```bash
submit host-info.yaml queue=dc-8g~$USER
```
# 需要指定队列queue=dc-8g~$USER，下一步骤中的my-docker才能执行该任务，特殊的测试机需要指定特殊的队列。

执行上述命令会打印提示信息如下:
```
submit_id=bf5e7ad7-839d-48ec-a033-23281323c750
submit /c/lkp-tests/jobs/host-info.yaml, got job id=$lab.1
```

- 运行my-docker执行测试任务
```
cd /c/compass-ci/provides
./my-docker
```
# my-docker脚本将会启动一个docker测试机，且该测试机队列queue=dc-8g～$USER，来执行上一步骤中提交的测试任务。

- 查看任务结果
my-docker脚本执行完毕后，等待约1分钟，任务结果文件将自动从测试机上传到compass-ci服务端的/srv/result目录下，可根据使用submit命令提交测试用例后打印出的job id（“got job id=”等号后面才是job id，submit_id=xxx并不是job id，只是一个代表该任务的唯一标识）查看任务结果。
请将下行命令中的$lab.1替换为上一步骤中打印出的job id。
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
如果需要测试自制的发行版，可使用工具将发行版iso文件制作成compass-ci需要的[rootfs](https://gitee.com/wu_fengguang/compass-ci/tree/master/doc/rootfs/compass-ci-use-rootfs)，详细制作方法请[参考文档](https://gitee.com/wu_fengguang/compass-ci/tree/master/doc/rootfs/how-to-get-rootfs)。

- 非root用户注册账号
执行部署集群脚本 install-cluster时已经为root用户注册帐号，非root用户也需要注册帐号才能提交任务。
注册帐号需要将帐号信息写入es数据库，只有在微服务es运行的状态下才能注册成功，可使用'docker ps  | grep es-server01'检查该容器是否在up状态。
该用户登录系统后直接使用build-my-info命令注册（该命令已添加到PATH环境变量中，直接执行即可）

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
