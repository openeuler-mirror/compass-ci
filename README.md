# Compass-CI 用户指南

## 简介


### 概念

Compass-CI 是一个可持续集成的软件平台。为开发者提供针对上游开源软件（来自 Github,Gitee,Gitlab 等托管平台）的测试服务、登录服务、故障辅助定界服务和基于历史数据的分析服务。通过Compass-CI，社区开发者可以将开源软件快速引入openEuler社区，并补充更多的测试用例，共同构建一个开放、完整的开源软件生态系统。


### 功能描述

- **测试服务**

	支持开发者基于本地设备开发，往 github 提交代码，Compass-CI 自动获取代码开展测试，并向开发者反馈测试结果。
	
- **调测环境登录**

	Compass-CI 提供 SSH 登录能力，测试过程中如果测出问题，开发者可根据需要登录环境进行调测。

- **测试结果分析**

	Compass-CI 记录历史测试结果，对外提供 web 及命令行接口，支持开发者针对已有的测试结果进行分析，挖掘影响测试结果的因素。

- **辅助定位**

	Compass-CI 在测试过程中可以自动识别错误信息，触发基于 git tree 的测试，找出引入问题模块的变化点。


### 架构简介
![Compass-CI架构](doc/pictures/compass-ci-architecture.png)
- **接入层**
  
  成为衔接Compass-CI 服务于开发者的纽带，同时提供内部设备管理的平台，提供web门户查阅测试结果、项目清单、ssh环境登录

- **服务层**
  
  提供测试服务、环境登录、结果分析、辅助定界、用户项目注册能力，为本项目的主要功能

- **支撑层**
  
  作为项目主体功能实现，详细描述资源编排、部署、构建、测试 等详细实现。

- **数据层**
  
  为项目提供数据处理服务，包括测试结果格式化及归档

- **资源层**
  
  提供硬件设备，作为Compass-CI 服务部署的设备以及测试的物理设备、虚拟机、容器资源；提供测试过程中依赖软件仓库及依赖仓库、部署服务器。


### 应用场景

- **聚合开发者测试用例**
	
	开发者向代码托管平台提交代码、测试用例、测试工具时，Compass-CI自动获取提交的代码开展构建测试，同时获取开发者编写到开源软件包的测试用例进行自动化测试，并反馈测试结果。

- **登录环境随时调测**

	测试过程中，发现有 Bug 时，可随时提供调测资源服务，登录到环境进行复现、调试。
	
- **快照数据分析对比**
	
	测试过程中，全面监控系统运行信息（CPU/MEM/IO/网络等），对测试过程中的数据做快照归档，提供多次测试之间快照数据分析对比能力，协助开发者对测试结果开展分析，找出影响测试结果的因素。
	
- **辅助定界**

	测试过程中，发现有 Bug 时，自动触发 Regression 机制，找出首次引入问题 Commit 信息。
	


## 使用Compass-CI
> 您只需要先注册自己的仓库，当您的仓库有commit提交时，构建测试会自动执行，并且可在我们的网站中查看结果。

-  注册自己的仓库

	如果您想在 `git push` 的时候, 自动触发测试, 那么需要把您的公开 git url 添加到如下仓库[upstream-repos](https://gitee.com/wu_fengguang/upstream-repos)。   
	```bash
	git clone https://gitee.com/wu_fengguang/upstream-repos.git
	less upstream-repos/README.md
	```

- `git push`
  
  更新仓库，自动触发测试

- 在网页中搜索并查看结果
  
    web: https://compass-ci.openeuler.org/jobs



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


## 呼吁合作
  - 增强 git bisect 能力
  - 增强数据分析能力
  - 增强数据结果可视化能力
