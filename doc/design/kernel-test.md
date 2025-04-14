# 背景
对linux的kernel进行构建和测试

# 需求
构建内核，使用构建产物进行测试

# 构建内核
## commit
内核的commit id

## config
/srv/cci/build-config/linux/randconfig-tests/configs
可以使用qemu-randconfig 项目批量生成

## 方案1
基于pkgbuild构建内核，生成vmlinuz和modules文件，提供给测试用例使用
job:
boottest:
ss:
  linux:
    commit:
    config:
提交此job.yaml会先基于pkgbuild构建job-1，在基于产物进行测试job-2
job-2:
kernel_uri: vmlinuz.cgz
modules_uri: modules.cgz
优点：当前已支持
缺点：PKGBUILD和commit/config不配套的问题

## 方案2
基于spec构建内核，采用原生开发流水线
总流程：ccb 提交kernel构建到统一构建 -> 监控构建结果 -> 获取构建产物 -> 提交测试到compass-ci

如何生成构建产物：
ccb 提交需支持config/commit参数 -> 统一构建获取config使用该config进行构建 ->生成构建产物

如何使用构建的产物：
监控构建结果 -> 分析构建产物 -> 获取构建产物 -> 提交job包含构建产物（kernel_uri, modules_uri）
优点：采用原生开发的流水线
缺点：统一构建，原生开发均需要适配
不同点：方案2使用spec编译，方案1使用PKGBUILD编译


## 基于方案1的实现
submit host-info.yaml testbox=vm-2p8g ss.linux.commit=eaf554c397cd6b73e4a1fd3dfce8b293a0fd8db0 ss.linux.fork=linux-next ss.linux.config=/home/caoxl/yaml/randconfig-2022-07-14-23-05-43-fixed-2022-07-15-00-16-25

在命令行执行此命令，效果如下：
- 基于ss自动提交pkgbuild任务构建内核
- host-info的任务在内核构建完成后，基于生成的vmlinux,modules.cgz完成信息收集

### 构建job.yaml:
crystal.8211727.yaml:
os: openeuler
os_version: 20.03-fat
os_arch: aarch64
os_mount: container
docker_image: openeuler:20.03-fat
commit: eaf554c397cd6b73e4a1fd3dfce8b293a0fd8db0
upstream_repo: l/linux/linux-next
pkgbuild_repo: pkgbuild/aur-l/linux
upstream_url: https://mirrors.tuna.tsinghua.edu.cn/git/linux-next.git
upstream_dir: upstream
pkgbuild_source:
- https://git.archlinux.org/linux

waited:
- crystal.8211725: job_health
SCHED_PORT: "3000"
SCHED_HOST: 172.168.131.113
runtime: 36000
fork: linux-next
config: randconfig-2022-07-14-23-05-43-fixed-2022-07-15-00-16-25
upstream_commit: eaf554c397cd6b73e4a1fd3dfce8b293a0fd8db0
suite: pkgbuild
category: functional
pkgbuild:

### 构建产物：
kernel_uri: http://172.168.131.113:8800/kernel/aarch64/randconfig-2022-07-14-23-05-43-fixed-2022-07-15-00-16-25/eaf554c397cd6b73e4a1fd3dfce8b293a0fd8db0/vmlinuz
modules_uri: http://172.168.131.113:8800/kernel/aarch64/randconfig-2022-07-14-23-05-43-fixed-2022-07-15-00-16-25/eaf554c397cd6b73e4a1fd3dfce8b293a0fd8db0/modules.cgz


### 测试job.yaml：
crystal.8211725.yaml:
suite: test-auto-depend
tbox_group: vm-2p16g
os: openeuler
os_version: 20.03
os_arch: aarch64
need_memory: 300MB
runtime: 300
trinity:
ss:
  linux:
    fork: linux-next
    commit: eaf554c397cd6b73e4a1fd3dfce8b293a0fd8db0
    config: /home/caoxl/yaml/randconfig-2022-07-14-23-05-43-fixed-2022-07-15-00-16-25

kernel_uri: http://172.168.131.113:8800/kernel/aarch64/randconfig-2022-07-14-23-05-43-fixed-2022-07-15-00-16-25/eaf554c397cd6b73e4a1fd3dfce8b293a0fd8db0/vmlinuz
modules_uri: http://172.168.131.113:8800/kernel/aarch64/randconfig-2022-07-14-23-05-43-fixed-2022-07-15-00-16-25/eaf554c397cd6b73e4a1fd3dfce8b293a0fd8db0/modules.cgz
wait:
  crystal.8211727:
    job_health: success
