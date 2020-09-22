# Crystal-CI Introduction

## 简单说明














//kaitian


概念

Compass-CI 是一个可持续集成的软件平台。为开发者提供针对上游开源软件（来自 Github,Gitee,Gitlab 等托

管平台）的测试服务、登录服务、故障辅助定界服务、基于历史数据的分析服务。通过 Compass-CI，社区开发者将

开源软件快速引入 openEuler 社区，补充更多的测试用例，共同构建一个健康完善的开源软件生态。

背景

开源社区的软件质量保障一直是一个难题，不同的开源软件质量差别较大，同时当前社区测试系统一般以测试为

主，较少考虑社区开发者与测试系统的协同能力。

开源软件大多数基于个人 PC 开发及调测，缺乏强大易用的多元化测试集群环境。一般测试系统主要关注发现问

题，缺乏为开发者提供软件调测、调优、定位、复现能力。

openEuler 开放 Compass-CI 测试平台，为开源软件提供基于鲲鹏集群测试服务，一键式登录调测、自动 git

bisect、测试结果分析，大大提升社区开发者的开发调测体验。

功能描述

• 测试服务

支持开发者基于本地设备开发，往 github 提交代码，Compass-CI 自动获取代码开展测试，并向开发者反馈

测试结果。

• 调测环境登录

Compass-CI 提供 SSH 登录能力，测试过程中如果遇到有问题，开发者可根据需要环境进行登录调测 。

• 测试结果比较

Compass-CI 记录历史测试结果，对外提供 web 及命令行接口，支持开发者针对已有的测试结果进行分析，挖

掘影响测试结果的因素。

• bug 辅助定界

Compass-CI 测试过程中自动识别错误信息，触发基于 git tree 的测试，找出引入问题模块的变化点。

应用场景

• 应用场景1

聚合开发者测试用例：开发者往代码托管平台提交代码、测试用例、测试工具时，Compass-CI 自动获取提交的

代码开展构建测试，同时获取开发者编写到开源软件包的用例自动化测试，并反馈测试结果。

• 应用场景2

测试过程中，全面监控系统运行信息（CPU/MEM/IO/网络等），对测试过程数据快照归档，提供多次测试之间

快照数据分析对比能力，协助开发者对测试结果开展分析，找出影响测试结果的因素。

• 应用场景3

Compass-CI

应用场景

iSula-build 目前的应用场景很明确，可以在通用场景无缝替换 docker build 构建容器镜像，同时提供了上述涉

及的新特性。

测试过程中，发现有 Bug 时，自动触发 Regression 机制，找出首次引入问题 Commit 信息。

• 应用场景4

测试过程中，发现有 Bug 时，可随时提供调测资源服务，登录到环境进行复现、调试。

Compass-CI 优点

Compass-CI 集开发调测、测试服务、测试结果分析、辅助定位为一体的综合平台，打造社区开发者极致开发体

验。相比业绩其它持续集成软件相比，Compass-CI 平台具有如下特点：软件测试更简单、bug 调测更便捷、测试分

析数据更全面。

下一步计划：

1、优化 git bisect 精准率及效率

2、优化数据分析联动能力，让数据分析更加聚焦

3、数据可视化优化，更加友好展示数据比较结果。

4、增强登录认证机制，如：GPG 认证

5、优化部署效率









## 快速入门

- 前提条件














// shengde
  1. 如何申请账号
       通过向compass-ci@openeuler.io发邮件申请
       配置default

       申请邮件：
         - 邮件标题：'apply account'
	 - 收件地址：compass-ci@139.com
         - 公钥：附件方式添加公钥
	 - url: 开源社区提交过commit的url地址
           - 例：https://github.com/torvalds/linux/commit/7be74942f184fdfba34ddd19a0d995deb34d4a03

       回复邮件内容：

             account_uuird: xxxxxx
             SCHED_HOST:   xxx.xxx.xxx.xxx
             SCHED_PORT:   10000


















## 2. 建立本地环境（构建一个能够提交job的环境）
- 下载lkp-tests, 安装依赖包并配置环境变量
       ```bash
       git clone http://gitee.com/wu_fengguang/lkp-tests.git
       cd lkp-tests
       make install
       ```

- 配置lab
  - 打开lkp-tests/include/lab/z9
	```yaml
	SCHED_HOST: ip
	SCHED_PORT: port
	```
  - 新建$HOME/.config/compass-ci/defaults/$USER.yaml
	```yaml
	lab: z9
	```










## 3. 注册自己的仓库

如果您想在git push的时候, 自动触发测试, 那么需要把您的公开git url添加到如下仓库
[upstream-repos](https://gitee.com/wu_fengguang/upstream-repos)
	git clone https://gitee.com/wu_fengguang/upstream-repos.git
	less upstream-repos/README.md















# Job的定义和提交

## 一、job yaml文件如何写？

### job yaml的简介
	
- job yaml是测试描述和执行的基本单元。
- 它是以[YAML]的格式编写(http://yaml.org/YAML_for_ruby.html)。
- 所有job文件位于**```$LKP_SRC/jobs```**路径下。

### job yaml的结构

#### 1、yaml的标识头部（必选）

- 每一个job文件的开始部分，都有一些基础的描述信息，称之为yaml的Header。
- 头部主要有suite和category，suite是测试套的名称。category是测试类型，
  包括benchmarch（性能测试）/functional（功能测试）/noise-benchmark（不常用）。
	
  ```yaml
        suite: netperf
        category: benchmark
  ```	
#### 2、测试脚本和参数（必选）

- Job yaml是以键:值的格式编写，如果该键与下面路径中的某个脚本文件相匹配，则将其视为可执行脚本
  
     ```$LKP_SRC/setup
        $LKP_SRC/monitors
        $LKP_SRC/daemon
        $LKP_SRC/tests
      ```
- 测试脚本位于```**$LKP_SRC/tests**```，```**$LKP_SRC/daemon**```。
- 参数值是一个字符串或字符串数组，
  每个测试脚本将在其文件头的注释中记录可接受的参数(它将作为环境变量传递)。

	```yaml
        netserver:
        netperf:
            runtime: 10s
            test:
            - TCP_STREAM
            - UDP_STREAM
            send_size:
            - 1024
            - 2048
        ```
#### 3、测试资源相关变量（必选）

- SUT/schduler/部署等资源相关变量。
		
	```yaml
        testbox: vm-hi1620-2p8g
        os: openeuler
        os_version: 20.03
        os_arch: aarch64
	```  
#### 4、系统设置脚本（可选）

- 设置脚本位于```**$LKP_SRC/setup**``` 目录。
- 设置脚本将在测试脚本之前运行，主要是用于启停一些依赖性服务或工具，或者配置测试所需的参数等。

  ```yaml
        cgroup2: #$LKP_SRC/setup/cgroup2 executable script
        memory.high: 90%
        memory.low: 50%
        memory.max: max
        memory.swap.max:
        io.max:
        io.weight:
        rdma.max:
  ```
#### 5、监控脚本（可选）

- 位于```**$LKP_SRC/monitors**```
- 监视器在运行基准测试时捕获性能统计数据。
- 对性能分析和回归根源有价值。
		  
  ```yaml
      proc-vmstats:
           nterval: 5
  ```
### Job yaml的扩展和解释可参考：
```
【job的定义到执行】（https://gitee.com/wu_fengguang/lkp-tests/blob/master/jobs/README.md）
```
## 二、 提交测试任务

- 环境准备就绪，就可以提交job给调度器。
- 测试任务的结果见结果查看章节。

#### 1、 submit命令的用法：
```
- Usage: submit [options] jobs...
      submit test jobs to scheduler
- options:
        - s, --set 'KEY: VALUE'   #add YAML hash to job
        - o, --output DIR         #save job yaml to DIR/
        - a, --auto-define-files  #auto add define_files
        - c, --connect            #auto connect to the host
        - m, --monitor            # monitor job status: use -m 'KEY: VALUE' to add rule"
```
#### 2、以netperf为例，提交job文件
```
     **submit netperf.yaml** 
```









// weitao
  5、查看测试结果
  	local: /srv/result/$suite/$testbox/$date/$jobid/ file types under it
        通过job web 直接查看任务结果
        通过命令行查询














#### 6、比较测试结果

> After the test has been completed, use conditions to query data, then combine data to multiple matrices. And that will compute each matrix average and standard deviation to compare test case performance changes in a specific dimension. At last, print compare result in pretty format.

- methods
    - web
        - Compass CI/compare
    - command
        - `compare conditions -d dimension`

- example result

    ```
    os=openeuler/os_arch=aarch64/tbox_group=vm-hi1620-2p8g


                      20                               1  metric
    --------------------  ------------------------------  ------------------------------
          fails:runs        change        fails:runs
               |               |               |
              8:21          -38.1%            0:1         last_state.daemon.sshd.exit_code.1
              1:21           -4.8%            0:1         last_state.daemon.sshd.exit_code.2
              1:21           -4.8%            0:1         last_state.setup.disk.exit_code.1
              1:21           -4.8%            0:1         last_state.test.dbench.exit_code.99
              1:21           -4.8%            0:1         last_state.test.email.exit_code.7


                      20                               1  metric
    --------------------  ------------------------------  ------------------------------
              %stddev       change            %stddev
                 \             |                 \
            0.02 ± 265%   +2259.8%          0.57          mpstat.cpu.all.soft%
            0.48 ± 299%   +1334.9%          6.90          mpstat.cpu.all.sys%
         2760.71 ± 164%    +292.6%      10838.00          proc-vmstat.nr_dirty_background_threshold
         5522.10 ± 164%    +292.6%      21680.00          proc-vmstat.nr_dirty_threshold
    ```














// zhengde
  7. 提交borrow任务
	fields:
		sshd:
		runtime:

  	os env
	testbox list
	submit -c -m borrow.yaml














  8. 提交 bisect任务
    The bisect task will find the first commit information which introduced the error in a git repo.

    Refer to $LKP_SRC/jobs/bisect.yaml.
    Required fields:
      bisect:
        job_id: 
        error_id:

    Field description:
      job_id: 
      submit a job and get a $job_id.
      error_id:
      search $job_id in compass-ci web and get the $error_ids, select a $error_id from $error_ids for bisect. 
  
    Command:
      submit bisect.yaml

    Result:
      will get a email if bisect successed.


## 高级功能













- 添加OS支持
  nfs/cifs

  osimage(initramfs)

  制作一个initramfs启动的cgz镜像，当系统内核启动时，直接从打包的cgz镜像中导出rootfs，在内存中展开文件系统，利用磁盘的高速缓存机制让系统直接在内存中读写文件，以提升系统的I/O性能。

    [此处以openEuler为例]
    1. 获取对应os版本的rootfs
    	1) 通过docker获取rootfs 
		a) 下载openEuler官方提供的docker镜像压缩包
		   wget https://repo.openeuler.org/openEuler-20.03-LTS/docker_img/aarch64/openEuler-docker.aarch64.tar.xz

		b) 加载docker镜像
		   docker load -i openEuler-docker.aarch64

		c) 启动openEuler容器
		   docker run -id openeuler-20.03-lts

		b) 拷贝docker的rootfs
		   docker cp -a  docker run -d openeuler-20.03-lts:/    openEuler-rootfs

	2) 通过qemu.img(qcow2格式)获取rootfs (此处以centos为例)
		a) 下载openEuler官方网站提供的qcow2格式镜像
		  wget https://repo.openeuler.org/openEuler-20.03-LTS/virtual_machine_img/aarch64/openEuler-20.03-LTS.aarch64.qcow2.xz
		b) 使用{compass-ci}/container/qcow2rootfs 制作rootfs
		  cd {compass-ci}/container/qcow2rootfs
		  ./run  openEuler-20.03-LTS.aarch64.qcow2.xz   /tmp/openEuler-rootfs

    2. 定制rootfs
    	1) 使用chroot命令切换到rootfs中(此步骤需要root权限)
           	chroot openEuler-rootfs

    	2) 根据个人需要安装并配置服务
	   a) 修改root密码
	   b) 配置ssh服务
	   c) 检查系统时间
	   d) 如果使用docker制作osimage还需要以下操作：
	   	安装所需版本内核
		    从centos官方网站下载内核rpm包
		    使用yum进行安装
		删除docker环境变量文件
		    rm /.dockerenv文件

    3. 退出rootfs，并打包
    	cd $rootfs
 	find . | coip -o -Hnewc |gzip -9 > $os_name.cgz

    FAQ:
     Q:如果出现报错：

     ...
     [    0.390437] List of all partitions:
     [    0.390806] No filesystem could mount root, tried: 
     [    0.391489] Kernel panic - not syncing: VFS: Unable to mount root fs on unknown-block(0,0)
     ...
     [    0.399404] Memory Limit: none
     [    0.399749] ---[ end Kernel panic - not syncing: VFS: Unable to mount root fs on unknown-block(0,0) ]---

     A: 1)启动内存不足，增加内存可解决。
        2)内核文件权限不足，给予644权限。
	
     Q:如果打包镜像体积过大，会消耗很大内存。
     A:建议用户根据具体需要对rootfs进行裁剪

   











// baijing, zhangyu
- 添加测试用例
 refer to
 https://gitee.com/wu_fengguang/lkp-tests/blob/master/doc/add-testcase.md 














// shaofei
- PKGBUILD 构建 














// wangyong
- depends














- 本地搭建compass-ci 服务器节点

      概述：在openEuler系统一键部署compass-ci环境

      声明：目前已支持 openEuler-aarch64-20.03-LTS 系统环境
            以下配置仅供参考

      - 准备工作

              - 硬件
                      服务器类型：ThaiShan200-2280 (建议)
                            架构：aarch64
                            内存：>= 8GB
                             CPU：64 nuclear       (建议)
                            硬盘：>= 500G

              - 软件
                              OS：openEuler-aarch64-20.03 LTS
                             git：2.23.0版本       (建议)
                        预留空间：>= 300G
                            网络：可以访问互联网

      说明: openEuler系统安装
      https://openeuler.org/zh/docs/20.03_LTS/docs/Installation/%E5%AE%89%E8%A3%85%
E5%87%86%E5%A4%87.html

      - 操作指导

              1. 登录openEuler系统

              2. 创建工作目录并设置文件权限

                      mkdir demo && cd demo && umask 002

              3. 克隆compass-ci项目代码到demo目录

                      git clone https://gitee.com/wu_fengguang/compass-ci.git

              4. 执行一键部署脚本install-tiny

                      cd compass-ci/sparrow && ./install-tiny



## todo call for Cooperation
  improve git bisect 
  improve 数据分析
  improve 数据结果可视化


