# Compass-CI 用户指南

## 简介


### 概念

Compass-CI 是一个可持续集成的软件平台。为开发者提供针对上游开源软件（来自 Github,Gitee,Gitlab 等托管平台）的测试服务、登录服务、故障辅助定界服务和基于历史数据的分析服务。通过Compass-CI，社区开发者可以将开源软件快速引入openEuler社区，并补充更多的测试用例，共同构建一个开放、完整的开源软件生态系统。


### 功能描述

- 测试服务

	支持开发者基于本地设备开发，往 github 提交代码，Compass-CI 自动获取代码开展测试，并向开发者反馈测试结果。
	
- 调测环境登录

	Compass-CI 提供 SSH 登录能力，测试过程中如果测出问题，开发者可根据需要登录环境进行调测 。

- 测试结果分析

	Compass-CI 记录历史测试结果，对外提供 web 及命令行接口，支持开发者针对已有的测试结果进行分析，挖掘影响测试结果的因素。

- 辅助定位

	Compass-CI 在测试过程中可以自动识别错误信息，触发基于 git tree 的测试，找出引入问题模块的变化点。

### 应用场景

- 聚合开发者测试用例
	
	开发者向代码托管平台提交代码、测试用例、测试工具时，Compass-CI自动获取提交的代码开展构建测试，同时获取开发者编写到开源软件包的测试用例进行自动化测试，并反馈测试结果。

- 登录环境随时调测

	测试过程中，发现有 Bug 时，可随时提供调测资源服务，登录到环境进行复现、调试。
	
- 快照数据分析对比
	
	测试过程中，全面监控系统运行信息（CPU/MEM/IO/网络等），对测试过程中的数据做快照归档，提供多次测试之间快照数据分析对比能力，协助开发者对测试结果开展分析，找出影响测试结果的因素。
	
- 辅助定界

	测试过程中，发现有 Bug 时，自动触发 Regression 机制，找出首次引入问题 Commit 信息。
	


## 使用Compass-CI

### 前提条件


- 申请账号

    您可以通过向**compass-ci@139.com**发送邮件进行账号申请，邮件标题为"**apply account**"，在正文中提供**您向开源项目提交过的commit的url地址**(我们将根据此进行审查并决定是否发放账号)，并以附件方式添加**准备用来提交任务的个人电脑的公钥**。  
    发送邮件后，将收到一封回复邮件，邮件回复内容如下：
	
	    account_uuird: xxxxxx
    	    SCHED_HOST: ip      # 下面配置中将会使用到的ip地址
    	    SCHED_PORT: port    # 下面配置中将会使用到的端口

-  构建本地可以提交job的环境
	
	- 下载安装[lkp-tests](https://gitee.com/wu_fengguang/lkp-tests)
       ```bash
       git clone https://gitee.com/wu_fengguang/lkp-tests.git
       cd lkp-tests
       sudo make install
       ```
	
	- 配置lab
	
	  - 编辑`.../lkp-tests/include/lab/z9`
		```yaml
		SCHED_HOST: ip      # 申请账号时回复邮件中的ip
		SCHED_PORT: port    # 申请账号时回复邮件中的端口
		```
	  - 新建`$HOME/.config/compass-ci/defaults/$USER.yaml` 内容如下
		```yaml
		lab: z9
		```

-  注册自己的仓库

	如果您想在 `git push` 的时候, 自动触发测试, 那么需要把您的公开 git url 添加到如下仓库[upstream-repos](https://gitee.com/wu_fengguang/upstream-repos)。   
	```bash
	git clone https://gitee.com/wu_fengguang/upstream-repos.git
	less upstream-repos/README.md
	```

### 编写job yaml文件

#### job yaml简介
job yaml 是测试描述和执行的基本单元，以[YAML](http://yaml.org/YAML_for_ruby.html)的格式编写，所有 job 文件位于```$LKP_SRC/jobs```路径下。

#### job yaml的结构
	
- 标识头部 Header（必选）

    每一个job文件的开始部分，都有一些基础的描述信息，称之为yaml的Header。头部主要有suite和category，suite是测试套的名称。category是测试类型，包括benchmarch（性能测试）/functional（功能测试）/noise-benchmark（不常用）。
	
	```yaml
	suite: netperf       \\测试套名称
	category: benchmark  \\测试类型：benchmarch|functional|noise-benchmark
	```
	
- 测试脚本和参数（必选）

	- 测试脚本位于```$LKP_SRC/tests```，```$LKP_SRC/daemon```路径下。job yaml中写入与上述路径中脚本相匹配的文件，将其视为可执行脚本。
		  
	```
	$LKP_SRC/setup
	$LKP_SRC/monitors
	$LKP_SRC/daemon
	$LKP_SRC/tests
	```
	- 参数值作为环境变量传递，每个测试脚本将在其文件头的注释中记录可接受的参数。

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
- 测试资源相关变量（必选）

	SUT/schduler/部署等资源相关变量。	
	```yaml
	    testbox: vm-hi1620-2p8g
	    os: openeuler
	    os_version: 20.03
	    os_arch: aarch64
	```
- 系统设置脚本（可选）

	位于```$LKP_SRC/setup```路径下。设置脚本将在测试脚本之前运行，主要是用于启停一些依赖性服务或工具，或者配置测试所需的参数等。

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
- 监控脚本（可选）
	
	位于```$LKP_SRC/monitors```路径下。 监视器在运行基准测试时可以捕获性能统计数据，对性能分析和回归根源有价值。
	
	```yaml
	proc-vmstats:
	nterval: 5
	```

**了解更多job yaml相关知识**  [Job definition to execution](https://gitee.com/wu_fengguang/lkp-tests/blob/master/jobs/README.md)


###  提交测试任务


使用```submit```关键字提交测试任务，以netperf为例，命令如下。
```bash
submit netperf.yaml
```


submit命令更多参数设置方法如下。
```
- Usage: submit [options] jobs...
      submit test jobs to scheduler
- options:
        - s, --set 'KEY: VALUE'   #add YAML hash to job
        - o, --output DIR         #save job yaml to DIR
        - a, --auto-define-files  #auto add define_files
        - c, --connect            #auto connect to the host
        - m, --monitor            # monitor job status: use -m 'KEY: VALUE' to add rule"
```


###  查看测试结果


- 生成与存储测试结果
	测试执行机完成测试任务后，将结果保存到日志文件中，并上传至服务器，按照```$suite/$tbox_group/$date/job_id```的目录结构存储在本地```/srv/result```目录。
	extract-stats 服务将提取本地日志文件中的数据，生成与日志文件对应的json文件，并将汇总后的结果存储到obs数据库(ES)对应id的job中。


- web页面查看结果:
	- 点击链接查看obs数据库（ES）中的结果：https://compass-ci.openeuler.org/jobs

	- 点击链接查看文件中的结果,示例：http://124.90.34.227:11300/result/iperf/dc-2g--xiao/2020-09-21/crystal.83385/， 文件分为两类：

		- 由测试执行机上传的日志文件：
		boot-time, diskstats.gz, interrupts.gz, ...等。
		
		- 由extract-stats服务生成的json文件：
		boot-time.json, diskstats.json, interrupts.json,stats.json, ... 等。
		json 文件对应每一个日志文件提取后的结果，stats.json为汇总后的结果。


###  比较测试结果

测试完成后，Compass-CI通过条件查询数据并将数据合并为多个矩阵，计算每个矩阵的平均值和标准差，以比较测试用例在特定维度的性能变化。最后，将比较结果打印输出。


可以通过如下两种方式比较测试结果：

-  通过compare web比较
    Compass CI/compare
	
-  通过命令行比较
     ```
	 compare conditions -d dimension
	```

示例比较测试结果如下。
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


###   提交borrow任务

borrow任务是指通过提交任务的方式申请环境，提交borrow任务的yaml文件请参考lkp-tests/jobs/borrow-1h.yaml。

1. yaml文件配置说明：

	- 必填字段：
	```
	  sshd:
		pub_key  \\将用户的公钥信息添加到job中
		email    \\ 配置用户邮箱地址
	  runtime    \\申请环境的使用时间 h/d/w
	  testbox    \\申请环境的规格
	```
	- 选填字段：
	```
	  os         \\申请环境的操作系统参数
	  os_arch
	  os_version
	```

2. 提交任务

	执行命令```submit -m -c borrow-1h.yaml```，可以提交borrow任务并自动ssh连接到申请的环境当中。


###  提交 bisect 任务

bisect 任务可以找到首次在git repo中引入问题的commit信息。提交bisect任务的yaml文件请参考 $LKP_SRC/jobs/bisect.yaml。

1. yaml文件配置说明：
    - 必填字段：
	```
      bisect:
      job_id:    \\提交job的job_id
      error_id:  \\在Compass-CI网页上搜索$job_id，得到$error_ids，从$error_ids中选择一个$error_id。
	```
2. 提交任务
      执行命令```submit bisect.yaml```，提交成功后会收到通知邮件。



## 高级功能

### 添加OS支持

制作一个initramfs启动的cgz镜像，当系统内核启动时，直接从打包的cgz镜像中导出rootfs，在内存中展开文件系统，利用磁盘的高速缓存机制让系统直接在内存中读写文件，以提升系统的I/O性能。

#### 操作步骤

   1. 获取对应os版本的rootfs（以openEuler为例）
        - 通过docker获取rootfs
		
            1) 下载openEuler官方提供的docker镜像压缩包
		
                ```bash
                wget https://repo.openeuler.org/openEuler-20.03-LTS/docker_img/aarch64/openEuler-docker.aarch64.tar.xz
                ```	
            2) 加载docker镜像		   
                ```bash
                docker load -i openEuler-docker.aarch64
                ```

            3) 启动openEuler容器			   
                ```bash
                docker run -id openeuler-20.03-lts
                ```
            4) 拷贝docker的rootfs			   
                ```bash
                docker cp -a  docker run -d openeuler-20.03-lts:/ openEuler-rootfs
                ```
        - 通过qemu.img(qcow2格式)获取rootfs (以openEuler为例)
		
		
            1) 下载openEuler官方网站提供的qcow2格式镜像		
                ```bash
                wget https://repo.openeuler.org/openEuler-20.03-LTS/virtual_machine_img/aarch64/openEuler-20.03-LTS.aarch64.qcow2.xz
                ```
            2) 使用{compass-ci}/container/qcow2rootfs 制作rootfs
                ```bash
                cd {compass-ci}/container/qcow2rootfs
                ./run  openEuler-20.03-LTS.aarch64.qcow2.xz   /tmp/openEuler-rootfs
                ```
   2. 定制rootfs
        1. 使用chroot命令切换到rootfs中(此步骤需要root权限)         	
            ```bash
            chroot openEuler-rootfs
            ```
        2. 根据个人需要安装并配置服务
            
            a. 修改root密码
            b. 配置ssh服务
            c. 检查系统时间
            d. 如果使用docker制作osimage还需要以下操作：
			>	1. 安装所需版本内核
			>	2. 从centos官方网站下载内核rpm包
			>	3. 使用yum进行安装
			>	4. 删除docker环境变量文件

   3. 退出rootfs，并打包
        ```bash
        cd $rootfs
        find . | coip -o -Hnewc |gzip -9 > $os_name.cgz
        ```
#### FAQ
1. 日志报错 “Unable to mount root fs on unknown-block” 
    - 问题现象
        ```bash
        [    0.390437] List of all partitions:
        [    0.390806] No filesystem could mount root, tried: 
        [    0.391489] Kernel panic - not syncing: VFS: Unable to mount root fs on unknown-block(0,0)
		...
        [    0.399404] Memory Limit: none
        [    0.399749] ---[ end Kernel panic - not syncing: VFS: Unable to mount root fs on unknown-block(0,0) ]---
        ```
	- 解决方法
		
		1）启动内存不足，增加内存可解决。
		2）内核文件权限不足，给予644权限。
	
2. 系统运行缓慢
	
	- 问题现象

        打包镜像体积过大，会消耗很大内存
	- 解决方法

        建议用户根据具体需要对rootfs进行裁剪。


### 添加测试用例
 参考文档详见：[添加测试用例](https://gitee.com/wu_fengguang/lkp-tests/blob/master/doc/add-testcase.md)


### PKGBUILD 构建 

1. 概述：

         使用PKGBUILD完成上游项目源代码的编译构建，同一项目可以使用不同PKGBUILD完成项目编译构建过程。
         PKGBUILD相关参考文档：https://wiki.archlinux.org/index.php/PKGBUILD

2. 步骤：

    1) 注册仓库
        如果您想在git push的时候, 自动触发测试, 那么需要把您的公开git url添加到如下仓库[upstream-repos](https://gitee.com/wu_fengguang/upstream-repos)
		```bash
		git clone https://gitee.com/wu_fengguang/upstream-repos.git
	  	less upstream-repos/README.md
		```

    2) 执行构建测试
          项目代码更新后自动触发构建任务，无需其他操作。

    3) 查看结果
          web: https://compass-ci.openeuler.org/jobs

    4) 备注
          目前提供archlinux下已有PKGBUILD项目构建测试，暂不支持自主导入PKGBUILD文件。
          PKGBUILD存放路径： /srv/git/archlinux/*/*/PKGBUILD


### depends

- 依赖包构建
	流程: 以下默认使用debian:sid版本进行,如果使用其他OS跑测试用例，则需要在lkp-tests/distro/adaptation/下将包名以键值对的形式写入对应OS的文件中
	> 例： `echo 'apache2: httpd' >> lkp-tests/distro/adaptation/openeuler`
	
	1) 在lkp-tests/distro/depends/下新建一个与测试用例同名的文件
		`vim lkp-tests/distro/depends/test`
	2) 将测试用例所需debian下的包名填入创建的文件中
		`echo "apache2" >> lkp-tests/distro/depends/test`
	3) 生成lkp-aarch64.cgz
		`./crystal-ci/container/lkp-initrd/run`
	4) 提交测试用例
		`submit test.yaml`
	5) 查看结果
		https://compass-ci.openeuler.org/jobs



### 本地搭建compass-ci 服务器节点

在openEuler系统一键部署compass-ci环境，当前已支持 openEuler-aarch64-20.03-LTS 系统环境，以下配置仅供参考。

#### 准备工作      
- 硬件
        服务器类型：ThaiShan200-2280 (建议)
        架构：aarch64
        内存：>= 8GB
        CPU：64 nuclear (建议)
        硬盘：>= 500G
        
- 软件
        OS：openEuler-aarch64-20.03 LTS
        git：2.23.0版本 (建议)
        预留空间：>= 300G
        网络：可以访问互联网
		    							
	>**说明：**   
	>openEuler系统安装详细操作请参考[添加测试用例](https://openeuler.org/zh/docs/20.03_LTS/docs/Installation/%E5%AE%89%E8%A3%85%E5%87%86%E5%A4%87.html)   


#### 操作指导
1. 登录openEuler系统
     
2. 创建工作目录并设置文件权限
	```bash
	mkdir demo && cd demo && umask 002
	```
3. 克隆compass-ci项目代码到demo目录
	```bash
	git clone https://gitee.com/wu_fengguang/compass-ci.git
	```
4. 执行一键部署脚本install-tiny
	```bash
	cd compass-ci/sparrow && ./install-tiny
	```


## 呼吁合作
  - 增强 git bisect 能力
  - 增强数据分析能力
  - 增强数据结果可视化能力

## 下一步计划

1. 优化 git bisect 精准率及效率。
2. 优化数据分析联动能力，让数据分析更加聚焦。
3. 数据可视化优化，更加友好展示数据比较结果。
4. 增强登录认证机制，如：GPG 认证。
5. 优化部署效率。
