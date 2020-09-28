# Compass-CI 用户指南

## 简介


### 概念

Compass-CI 是一个可持续集成的软件平台。为开发者提供针对上游开源软件（来自 Github, Gitee, Gitlab 等托管平台）的测试服务、登录服务、故障辅助定界服务和基于历史数据的分析服务。通过 Compass-CI，社区开发者可以将开源软件快速引入 openEuler 社区，并补充更多的测试用例，共同构建一个开放、完整的开源软件生态系统。


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
	
	开发者向代码托管平台提交代码、测试用例、测试工具时，Compass-CI 自动获取提交的代码开展构建测试，同时获取开发者编写到开源软件包的测试用例进行自动化测试，并反馈测试结果。

- 登录环境随时调测

	测试过程中，发现有 Bug 时，可随时提供调测资源服务，登录到环境进行复现、调试。
	
- 快照数据分析对比
	
	测试过程中，全面监控系统运行信息（CPU/MEM/IO/网络等），对测试过程中的数据做快照归档，提供多次测试之间快照数据分析对比能力，协助开发者对测试结果开展分析，找出影响测试结果的因素。
	
- 辅助定界

	测试过程中，发现有 Bug 时，自动触发 Regression 机制，找出首次引入问题 Commit 信息。
	


## 使用 Compass-CI
> 当您注册之后，便可以编写 yaml 文件并通过我们的工具上传任务以进行自定义测试，测试功能将尽快上线。


-  注册自己的仓库

	如果您想在 `git push` 的时候, 自动触发测试, 那么需要把您的公开 git url 添加到如下仓库 [upstream-repos](https://gitee.com/wu_fengguang/upstream-repos)。   
	```bash
	git clone https://gitee.com/wu_fengguang/upstream-repos.git
	less upstream-repos/README.md
	```

### 编写 job yaml 文件

#### job yaml 简介
job yaml 是测试描述和执行的基本单元，以[YAML](http://yaml.org/YAML_for_ruby.html)的格式编写，所有 job 文件位于```$LKP_SRC/jobs```路径下。[$LKP_SRC](https://gitee.com/wu_fengguang/lkp-tests)

#### job yaml 的结构
	
- 标识头部 Header（必选）

    每一个 job 文件的开始部分，都有一些基础的描述信息，称之为 yaml 的 Header。头部主要有 suite 和 category，suite 是测试套的名称。category 是测试类型，包括 benchmarch（性能测试）/functional（功能测试）/noise-benchmark（不常用）。
	
	```yaml
	suite: netperf       \\测试套名称
	category: benchmark  \\测试类型：benchmarch|functional|noise-benchmark
	```
	
- 测试脚本和参数（必选）

	- 测试脚本位于```$LKP_SRC/tests```，```$LKP_SRC/daemon```路径下。job yaml 中写入与上述路径中脚本相匹配的文件，将其视为可执行脚本。
		  
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

**了解更多 job yaml 相关知识**  [Job definition to execution](https://gitee.com/wu_fengguang/lkp-tests/blob/master/jobs/README.md)


###  提交测试任务

###  查看测试结果

###  比较测试结果

###  提交 borrow 任务

###  提交 bisect 任务

## 高级功能

### 添加 OS 支持

制作一个 initramfs 启动的 cgz 镜像，当系统内核启动时，直接从打包的 cgz 镜像中导出 rootfs，在内存中展开文件系统，利用磁盘的高速缓存机制让系统直接在内存中读写文件，以提升系统的 I/O 性能。

#### 操作步骤

   1. 获取对应 os 版本的 rootfs（以 openEuler 为例）
        - 通过 docker 获取 rootfs
		
            1) 下载 openEuler 官方提供的 docker 镜像压缩包
		
                ```bash
                wget https://repo.openeuler.org/openEuler-20.03-LTS/docker_img/aarch64/openEuler-docker.aarch64.tar.xz
                ```	
            2) 加载 docker 镜像		   
                ```bash
                docker load -i openEuler-docker.aarch64
                ```

            3) 启动 openEuler 容器			   
                ```bash
                docker run -id openeuler-20.03-lts
                ```
            4) 拷贝 docker 的 rootfs			   
                ```bash
                docker cp -a  docker run -d openeuler-20.03-lts:/ openEuler-rootfs
                ```
        - 通过 qemu.img(qcow2格式)获取  rootfs (openEuler为例)
		
		
            1) 下载 openEule r官方网站提供的 qcow2 格式镜像		
                ```bash
                wget https://repo.openeuler.org/openEuler-20.03-LTS/virtual_machine_img/aarch64/openEuler-20.03-LTS.aarch64.qcow2.xz
                ```
            2) 使用{compass-ci}/container/qcow2rootfs 制作rootfs
                ```bash
                cd {compass-ci}/container/qcow2rootfs
                ./run  openEuler-20.03-LTS.aarch64.qcow2.xz   /tmp/openEuler-rootfs
                ```
   2. 定制rootfs
        1. 使用chroot命令切换到 rootfs (此步骤需要 root 权限)         	
            ```bash
            chroot openEuler-rootfs
            ```
        2. 根据个人需要安装并配置服务
            
            a. 修改 root 密码
            b. 配置 ssh 服务
            c. 检查系统时间
            d. 如果使用 docker 制作 osimage 还需要以下操作：
			>	1. 安装所需版本内核
			>	2. 从 centos 官方网站下载内核rpm包
			>	3. 使用 yum 进行安装
			>	4. 删除 docker 环境变量文件

   3. 退出 rootfs，并打包
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
		2）内核文件权限不足，给予 644 权限。
	
2. 系统运行缓慢
	
	- 问题现象

        打包镜像体积过大，会消耗很大内存
	- 解决方法

        建议用户根据具体需要对 rootfs 进行裁剪。


### 添加测试用例
 参考文档详见：[添加测试用例](https://gitee.com/wu_fengguang/lkp-tests/blob/master/doc/add-testcase.md)


### PKGBUILD 构建 

1. 概述：

         使用 PKGBUILD 完成上游项目源代码的编译构建，同一项目可以使用不同 PKGBUILD 完成项目编译构建过程。
         PKGBUILD 相关参考文档：https://wiki.archlinux.org/index.php/PKGBUILD。

2. 步骤：

    1) 注册仓库
        如果您想在 git push 的时候, 自动触发测试, 那么需要把您的公开 git url 添加到如下仓库 [upstream-repos](https://gitee.com/wu_fengguang/upstream-repos)。
		```bash
		git clone https://gitee.com/wu_fengguang/upstream-repos.git
	  	less upstream-repos/README.md
		```

    2) 执行构建测试
          项目代码更新后自动触发构建任务，无需其他操作。

    3) 查看结果
          web: https://compass-ci.openeuler.org/jobs。

    4) 备注
          目前提供 archlinux 下已有 PKGBUILD 项目构建测试，暂不支持自主导入 PKGBUILD 文件。
          PKGBUILD 存放路径： /srv/git/archlinux/*/*/PKGBUILD。


### depends

- 依赖包构建
	流程: 以下默认使用 debian:sid 版本进行,如果使用其他OS跑测试用例，则需要在 lkp-tests/distro/adaptation/ 下将包名以键值对的形式写入对应 OS 的文件中
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



### 本地搭建 compass-ci 服务器节点

在 openEuler 系统一键部署 compass-ci 环境，当前已支持 openEuler-aarch64-20.03-LTS 系统环境，以下配置仅供参考。

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
	>openEuler 系统安装详细操作请参考[添加测试用例](https://openeuler.org/zh/docs/20.03_LTS/docs/Installation/%E5%AE%89%E8%A3%85%E5%87%86%E5%A4%87.html)   


#### 操作指导
1. 登录 openEuler 系统
     
2. 创建工作目录并设置文件权限
	```bash
	mkdir demo && cd demo && umask 002
	```
3. 克隆 compass-ci 项目代码到 demo 目录
	```bash
	git clone https://gitee.com/wu_fengguang/compass-ci.git
	```
4. 执行一键部署脚本 install-tiny
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
