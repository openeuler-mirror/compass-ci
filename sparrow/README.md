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
	>划分较小独立分区详细操作请参考[添加测试用例](https://gitee.com/wu_fengguang/compass-ci/blob/master/sparrow/1-storage/small)
	>划分较大独立分区详细操作请参考[添加测试用例](https://gitee.com/wu_fengguang/compass-ci/blob/master/sparrow/1-storage/large)

- 软件
        OS：openEuler-aarch64-20.03 LTS
        git：2.23.0版本 (建议)
        预留空间：>= 300G
        网络：可以访问互联网

	>**说明：**
	>openEuler 系统安装详细操作请参考[添加测试用例](https://openeuler.org/zh/docs/20.03_LTS/docs/Installation/%E5%AE%89%E8%A3%85%E5%87%86%E5%A4%87.html)

### 操作指导
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
5. 生成lkp-aarch64.cgz压缩包
	```bash
	cd /c/compass-ci/container/lkp-initrd && ./run
	```
6. 验证账号
	```bash
	cd /c/compass-ci/sbin && ./build-my-info.rb
	按照提示输入账号名和邮箱即可

7. 测试环境是否可以提交job测试
	```bash
	submit iperf.yaml testbox=vm-2p8g
	```

   执行上述命令正常情况下会提示信息如下：
   submit /c/lkp-tests/jobs/iperf.yaml failed, got job_id=0, error: Error resolving real path of '/srv/os/openeuler/aarch64/20.03/boot/vmlinuz': No such file or directory
   submit /c/lkp-tests/jobs/iperf.yaml failed, got job_id=0, error: Error resolving real path of '/srv/os/openeuler/aarch64/20.03/boot/vmlinuz': No such file or directory
   compass-ci搭建完毕，下面就可以开始进行测试了。

8. 下载rootfs（以下载openeuler/aarch64/20.03为例，需要在哪个系统上测试就去对应的/srv/os/目录下使用wget命令下载cgz文件包）
	```bash
	mkdir -p /srv/os/openeuler/aarch64/
	cd /srv/os/openeuler/aarch64
	wget http://124.90.34.227:11300/os/test/openeuler/aarch64/20.03.cgz
	```

9. 解压cgz包
	```bash
	gzip -dc 20.03.cgz | cpio -idv
	```

10. [使用 compass-ci 平台测试开源项目](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/test-oss-project.zh.md)

11. [编写测试用例](https://gitee.com/wu_fengguang/lkp-tests/blob/master/doc/add-testcase.md)

12. 使用[submit命令](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/submit-job.zh.md)提交测试用例
   注意：os_mount 必须指定为cifs

13. 运行测试任务
	```bash
	cd /c/compass-ci/providers/ && ./my-qemu.sh
	```

14. [查看任务结果](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/browse-results.zh.md),本地搭建compass-ci用户可在srv/result目录下根据job id查看output文件
	```bash
	cd /srv/result/iperf/$job_id/output
	```
