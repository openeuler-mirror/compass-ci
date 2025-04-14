# 1 需求概述

在提交 lkp-test 测试套时，能够定制虚拟机的磁盘和网卡

# 2 需求场景分析

## 2.1 需求来源

版本测试迁移：mugen 测试用例适配原生开发流水线

## 2.2 需求背景

lkp-tests mugen 测试套：https://gitee.com/compass-ci/lkp-tests/tree/master/programs/mugen

mugen ：https://gitee.com/openeuler/mugen

现状：仅支持场景一、五、七

场景一：单台虚拟机（ 测试套：abrt httpd ）
场景二：多台虚拟机（ 测试套：openscap openssh ）
场景三：单台虚拟机，添加多个网卡（ 测试套：firewalld ）
场景四：单台虚拟机，添加多个磁盘（ 测试套：mdadm ）
场景五：单台物理机（ 测试套：kernel freeipmi ）
场景六：多台虚拟机，添加多个网卡磁盘（ 测试套：os-basic ）
场景七：单台虚拟机，测试非官方发布的 repo 源

> 具体信息见 mugen/suite2cases 下的 json 文件
>
> "machine num": 2                           # 需要两台机器
> "add network interface": 2            # 需要两个网卡
> "add disk": [2, 2, 2, 2]                      # 需要四个2G磁盘

# 3 方案设计

**2.1 用户提交 job.yaml ，指定网卡数量、磁盘数量、磁盘大小**

```shell
submit job.yaml nr_nic=2 nr_disk=4 disk_size=2G
```

**2.2 qemu 创建和运行虚拟机**

https://gitee.com/openeuler/compass-ci/blob/master/providers/qemu/kvm.sh

添加网卡

- 获取网卡数量 nr_nic，默认为 1
- 对每个网卡生成 mac 地址
- 使用同一桥接接口 br0 ，配置虚拟机网络接口

```
-nic tap,model=virtio-net-pci,helper=/usr/libexec/qemu-bridge-helper,br=br0,mac=${mac}
```

添加磁盘

- 获取磁盘数量 nr_disk，默认为 nr_hdd_partitions + nr_ssd_partitions
- 获取磁盘大小 disk_size，默认为 128G
- 创建 qcow2 格式的虚拟硬盘镜像文件
- 指定虚拟硬盘驱动器

```
qemu-img create -q -f qcow2 "${qcow2_file}" $disk_size
-drive file=${qcow2_file},media=disk,format=qcow2,index=${index},if=virtio
```

# 附

网络接口信息

```shell
# ls /sys/class/net
br0
br0-nic
docker0
enp125s0f0
enp125s0f1
enp125s0f2
enp125s0f3
...
```

虚拟机配置参数

```shell
# cat /c/lab-z9/hosts/vm-2p8g
provider: qemu
template: kvm
nr_node: 1
nr_cpu: 2
memory: 8G
nr_hdd_partitions: 11
hdd_partitions:
  - /dev/vdb
  - /dev/vdc
  - /dev/vdd
  - /dev/vde
  - /dev/vdf
  - /dev/vdg
  - /dev/vdh
  - /dev/vdi
  - /dev/vdj
  - /dev/vdk
  - /dev/vdl
rootfs_disk:
  - /dev/vda
```
