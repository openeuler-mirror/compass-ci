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
1. 物理机与CCIC通信的网卡须支持pxe
2. 物理机hostname=服务器型号-CPU规格-内存规格-后缀，须集群唯一
3. 指定该物理机消费哪些队列的job，队列之间用','隔开，一般指定1～2个队列

mac="43-67-47-85-xx-xx"
hostname="taishan200-2280-2s64p-256g--a1001"
queues="taishan200-2280-2s64p-256g--a1001,iperf"

4. 注册物理机
SCHED_HOST, SCHED_PORT 是CCI集群的调度器HOST/PORT
首选绑定mac和hostname,然后绑定hostname和queues
'''
curl -X PUT "http://${SCHED_HOST}:${SCHED_PORT}/set_host_mac?hostname=${hostname}&mac=${mac}"
curl -X PUT "http://${SCHED_HOST}:${SCHED_PORT}/set_host2queues?host=${hostname}&queues=${queues}"
'''

## 验证与添加host-file到lab-${lab}.git仓库中
提交host-info job到新添加的物理机上
'''
submit host-info.yaml testbox=taishan200-2280-2s64p-256g--a1001 queue=taishan200-2280-2s64p-256g--a1001
'''
如下信息，证明物理机已添加成功
submit_id=c6d1ef7d-a7d1-4d92-8e4c-85b911a85dd0
submit host-info.yaml, got job id=crystal.4009719

### 获取host-info结果
'''
id=crystal.4009719 (这个id是通过提交host-info job 获取的)
cd /srv/$(es-find id=$id | grep result_root| awk -F'"' '{print $4}')
'''

'''
tree
'''
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
├── program_list
├── stats.json
├── stderr
├── stderr.json
├── stdout
├── time
├── time.json
└── umesg

'''
cat host-info
'''
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
选择一块硬盘作为rootfs_disk, 本物理选择ssd_partitions中的第一块
所以删除 nr_ssd_partitions: 1
修改 ssd_partitions: 为rootfs_disk:
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

### 保存文件为host-file
保存修改后的文件为该物理机的hostname，并保存提交到lab-${lab}.git仓库中
lab-${lab}/hosts/taishan200-2280-2s64p-256g--a1001
