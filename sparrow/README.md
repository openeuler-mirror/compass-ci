# 本地搭建 compass-ci 服务器节点

在 openEuler 系统一键部署 compass-ci 环境，当前已支持 openEuler-aarch64-20.03-LTS 系统环境，以下配置仅供参考。

## 准备工作
- 硬件    
	服务器类型：ThaiShan200-2280 (建议)    
	架构：aarch64    
	内存：>= 32GB    
	CPU：64 nuclear (建议)    
	硬盘：>= 500G (建议划分独立分区)    
	
	>**说明：**    
	>[划分较小独立分区](https://gitee.com/wu_fengguang/compass-ci/blob/master/sparrow/1-storage/small)    
	>[划分较大独立分区](https://gitee.com/wu_fengguang/compass-ci/blob/master/sparrow/1-storage/large)    

- 软件    
	OS：openEuler-aarch64-20.03 LTS    
	git：2.23.0版本 (建议)    
	预留空间：>= 300G    
	网络：可以访问互联网    
	
	>**说明：**    
	>[openEuler 系统安装](https://openeuler.org/zh/docs/20.03_LTS/docs/Installation/%E5%AE%89%E8%A3%85%E5%87%86%E5%A4%87.html)

### 操作指导

#### 本地搭建compass-ci

1. 登录 openEuler 系统

2. 配置git账号
	```bash
	git config --global user.name "xxx"
	git config --global user.email "xxx@xxx.com"
	```

3. 设置文件权限并关闭SELINUX
	```bash
	umask 002 && setenforce 0
	```

	>**说明：**   
	>setenforce 0 只是暂时禁用SELINUX，需要修改/etc/selinux/config中的SELINUX=enforcing改为SELINUX=permissive或disabled才能长期有效    
	>umask 002 只是暂时设置umask值，需要修改/etc/bashrc中的umask值为002才能长期有效

4. 创建工作目录并克隆 compass-ci 项目代码
	```bash
	mkdir /c/ && ln -s /c/compass-ci /c/cci
 	git clone https://gitee.com/wu_fengguang/compass-ci.git
	```

5. 执行一键部署脚本 install-tiny
	```bash
	cd compass-ci/sparrow && ./install-tiny
	```

#### 提交测试任务前的准备

1. 生成lkp-aarch64.cgz压缩包
	```bash
	cd /c/compass-ci/container/lkp-initrd && ./run
	```
2. 验证账号
	```bash
	cd /c/compass-ci/sbin && ./build-my-info.rb
	```

3. 测试环境是否可以提交job测试
	```bash
	submit iperf.yaml testbox=vm-2p8g
	```

	执行上述命令正常情况下会提示信息如下:    
	submit /c/lkp-tests/jobs/iperf.yaml failed, got job_id=0, error: Error resolving real path of '/srv/os/openeuler/aarch64/20.03/boot/vmlinuz': No such file or directory    
	submit /c/lkp-tests/jobs/iperf.yaml failed, got job_id=0, error: Error resolving real path of '/srv/os/openeuler/aarch64/20.03/boot/vmlinuz': No such file or directory    
	compass-ci搭建完毕，执行步骤4下载所需要的rootfs文件就可以开始进行测试了。

4. 下载rootfs文件（根据所需要的rootfs在[该目录](http://124.90.34.227:11300/os/)下获取对应版本的cgz文件）
	```bash
	mkdir -p /srv/os/openeuler/aarch64/20.03
	cd /srv/os/openeuler/aarch64/20.03
	wget http://124.90.34.227:11300/os/openeuler/aarch64/20.03.cgz
	```

5. 解压rootfs cgz 文件
	```bash
	gzip -dc 20.03.cgz | cpio -idv
	```

#### 提交测试任务到本地compass-ci
本文以测试用例iperf.yaml为例

1. [使用 compass-ci 平台测试开源项目](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/test-oss-project.zh.md)

2. 根据测试需要[编写测试用例](https://gitee.com/wu_fengguang/lkp-tests/blob/master/doc/add-testcase.md)和[编写PKGBUILD](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/write-PKGBUILD.zh.md)

3. 使用[submit命令](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/submit-job.zh.md)提交测试用例
	```bash
	submit iperf.yaml
	```

#### 运行测试任务并查看任务结果

1. 运行测试任务
	```bash
	cd /c/compass-ci/providers/ && ./my-qemu.sh
	```

2. 在本地/srv/result/目录下根据测试用例名称/日期/[testbox](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/submit-job.zh.md)/[os-os_version-os_arch](https://gitee.com/wu_fengguang/compass-ci/tree/master/doc/job)/job_id[查看任务结果](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/browse-results.zh.md)(可用tab键自动补全多级目录方便查找)
	```bash
	cd /srv/result/iperf/2020-12-29/vm-2p8g/openeuler-20.03-aarch64/nolab.1
	cat output
	```

	>**说明：**
	>[登陆测试环境调测任务](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/%E5%A6%82%E4%BD%95%E7%99%BB%E5%BD%95%E6%B5%8B%E8%AF%95%E6%9C%BA%E8%B0%83%E6%B5%8B%E4%BB%BB%E5%8A%A1.md)
