# Compass-CI 集群（简称CCI）添加测试机
## 测试机消费job流程

testbox queues="taishan200-2280-2s64p-256g--a1001,iperf"

testbox				  CCI scheduler
   |					|
   |request job by mac			|
   |----------------------------------->| find hostname by mac
   |					| find queues by hostname
   |					| find job by queues	
   |					|-----------------
   |					|		 |
   |					|		 |
   |					|<----------------
   |					|
   |  			       reply job|
   |<-----------------------------------|

## 添加物理机
需要定义 mac, hostname, queues 三个变量。
1. mac
	物理机与CCI集群通信的网卡须支持pxe，需要提供该网卡的mac地址（从环境运维人员获取）
	mac="43-67-47-85-11-22" （实际mac为准，连接符号为英文中划线'-'）

2. hostname
	hostname格式为 服务器型号-CPU规格-内存规格--编号，须集群唯一（物理机规格从环境运维人员获取）
	以要添加的物理机为例
	服务器型号为：taishan200-2280
	CPU规格为：2s64p
	内存规格为：256g
	编号为：a1001（自定义）

	hostname="taishan200-2280-2s64p-256g--a1001"（实际hostname为准）

3. queues
	物理机消费job的队列列表，用来指定物理机有消费哪些队列的job的能力，
	该队列列表用英文','隔开，一般指定1～2个队列，
	格式为 "taishan200-2280-2s64p-256g--a1001,iperf"（iperf为自定义的队列，以实际需要消费的job队列为准）
	例如在注册物理机的时候指定如上queues，
	那么该物理机可以消费添加到taishan200-2280-2s64p-256g--a1001和iperf队列的任务，
	通常会注册一个和物理机hostname相同的队列。

	queues="taishan200-2280-2s64p-256g--a1001,iperf"


4. 注册物理机
首先绑定mac和hostname，然后绑定hostname和queues。
下面命令中的 ${mac},${hostname},${queues} 需要替换成上面定义的值。
SCHED_HOST, SCHED_PORT 是CCI集群的调度器HOST/PORT，如果已经部署完CCI集群服务端，可通过配置文件获取。

将定义好的 mac, hostname, queues 导入到shell中。
```
export mac="43-67-47-85-11-22"
export hostname="taishan200-2280-2s64p-256g--a1001"
export queues="taishan200-2280-2s64p-256g--a1001,iperf"
```
以便下面的命令可以直接使用 mac, hostname, queues变量

```
SCHED_HOST=$(cat /etc/compass-ci/service/service-env.yaml | grep 'SCHED_HOST' | awk '{print $2}')
SCHED_PORT=$(cat /etc/compass-ci/service/service-env.yaml | grep 'SCHED_PORT' | awk '{print $2}')
curl -X PUT "http://${SCHED_HOST}:${SCHED_PORT}/set_host_mac?hostname=${hostname}&mac=${mac}"
curl -X PUT "http://${SCHED_HOST}:${SCHED_PORT}/set_host2queues?host=${hostname}&queues=${queues}"
```

## 验证与添加host-file到lab-${lab}.git仓库中
提交任务host-info.yaml 到新添加的物理机上，提交任务之前需要在/c/lkp-tests/hosts目录下生成一个公共的host-file文件，用来指定由哪种类型的测试机来执行任务。
提交任务时，调度器会检查/c/lkp-tests/hosts目录下是否存在该类型测试机对应的文件，不存在将导致任务提交失败。本文直接复制一个已有的测试机类型的文件
到/c/lkp-tests/hosts目录下，对于选择物理机作为测试机，文件名只取$hostname中“--”之前的部分。
```
cp -ra /c/lkp-tests/hosts/taishan200-2280-2s64p-256g /c/lkp-tests/hosts/$(echo $hostname | awk -F'--' '{print $1}')
```
而我们要添加到/c/lab-${lab}.git仓库中的hostfile文件，文件名取完整的$hostname值，文件中的内容对应了物理测试机的详细规格（例如内存，mac地址，系统盘，数据盘等），
规格信息通过host-info.yaml任务获取，经过修改按照固定的格式编辑成$hostname文件，手动添加到/c/lab-${lab}仓库中。
```
submit host-info.yaml testbox=taishan200-2280-2s64p-256g--a1001 queue=taishan200-2280-2s64p-256g--a1001
```
如下信息，证明物理机已添加成功
submit_id=c6d1ef7d-a7d1-4d92-8e4c-85b911a85dd0
submit host-info.yaml, got job id=crystal.4009719

### 获取host-info结果
```
id=crystal.4009719 (这个id是通过提交host-info job 获取的)
cd /srv/$(es-find id=$id | grep result_root| awk -F'"' '{print $4}')
```

执行上述命令可进入任务结果目录，该目录下有如下文件：
.
├── boot-time
├── dmesg
├── dmesg.json
├── heartbeat
├── host-info
├── host-info.time
├── host-info.time.json
├── job.sh
├── job.yaml
├── kmsg
├── kmsg.json
├── last_state
├── last_state.json
├── meminfo.gz
├── meminfo.json
├── output
├── executed_programs
├── stats.json
├── stderr
├── stderr.json
├── stdout
├── time
├── time.json
└── umesg

```
cat host-info
```
memory: 255G
nr_hdd_partitions: 3
nr_ssd_partitions: 1
hdd_partitions:
  - /dev/disk/by-id/scsi-35000c500bd6a682b
  - /dev/disk/by-id/scsi-35000c500bd67fe1b
  - /dev/disk/by-id/scsi-350000399b8919301
ssd_partitions:
  - /dev/disk/by-id/ata-SAMSUNG_MZ7LH480HAHQ-00005_S45PNA2MB43116
mac_addr:
  - 84:46:fe:73:b4:19
  - 84:46:fe:73:b4:1a
  - 84:46:fe:73:b4:1b
  - 84:46:fe:73:b4:1c
  - 68:4a:ae:f4:ab:8a
  - 68:4a:ae:f4:ab:8b
  - 68:4a:ae:f4:ab:8c
  - 68:4a:ae:f4:ab:8d
  - 68:4a:ae:f4:ab:0a
  - 68:4a:ae:f4:ab:0b
  - 68:4a:ae:f4:ab:0c
  - 68:4a:ae:f4:ab:0d
arch: aarch64
nr_node: 4
nr_cpu: 128
model_name: Kunpeng-920
ipmi_ip: 9.3.6.1

### 设置rootfs_disk
编辑$hostname文件
```
lab=$(awk '/^lab:\s/ {print $2;exit}' /etc/compass-ci/defaults/*.yaml)
cd /c/lab-${lab}
mkdir -p hosts
cd hosts
# 此处的$hostname就是本文开头定义的变量$hostname的值，所有要添加的物理测试机都统一放在/c/lab-${lab}/hosts目录下。
vi $hostname
```
选择一块硬盘作为rootfs_disk, 本物理机选择ssd_partitions中的第一块
所以删除 nr_ssd_partitions: 1
修改 ssd_partitions: 为rootfs_disk:
根据host-info.yaml任务的结果文件host-info中的信息编辑好的$hostname文件内容如下：
```
memory: 255G
nr_hdd_partitions: 3
hdd_partitions:
  - /dev/disk/by-id/scsi-350000399b8919301
  - /dev/disk/by-id/scsi-35000c500bd67fe1b
  - /dev/disk/by-id/scsi-35000c500bd6a682b
rootfs_disk:
  - /dev/disk/by-id/ata-SAMSUNG_MZ7LH480HAHQ-00005_S45PNA2MB43116
mac_addr:
  - 84:46:fe:73:b4:19
  - 84:46:fe:73:b4:1a
  - 84:46:fe:73:b4:1b
  - 84:46:fe:73:b4:1c
  - 68:4a:ae:f4:ab:8a
  - 68:4a:ae:f4:ab:8b
  - 68:4a:ae:f4:ab:8c
  - 68:4a:ae:f4:ab:8d
  - 68:4a:ae:f4:ab:0a
  - 68:4a:ae:f4:ab:0b
  - 68:4a:ae:f4:ab:0c
  - 68:4a:ae:f4:ab:0d
arch: aarch64
nr_node: 4
nr_cpu: 128
model_name: Kunpeng-920
ipmi_ip: 9.3.6.1
```

### 保存文件为host-file
保存修改后的文件为该物理机的hostname，并保存提交到lab-${lab}.git仓库中
lab-${lab}/hosts/taishan200-2280-2s64p-256g--a1001
