# 自动化测试
本文以待测试仓库[sysbench](https://github.com/akopytov/sysbench)为例，测试用例sysbench-cpu.yaml，测试脚本sysbench-cpu和PKGBUILD文件均为/c/lkp-tests目录下已有的，为了方便git push该仓库触发自动化测试，实际使用的是fork该仓库后的[gitee](https://gitee.com/liu-yinsi/sysbench)地址。

1. [编写测试用例](https://gitee.com/wu_fengguang/lkp-tests/blob/master/doc/add-testcase.md)
	本文中测试用例使用/c/lkp-tests/jobs/sysbench-cpu.yaml，测试脚本使用/c/lkp-tests/tests/sysbench-cpu，测试用例和测试脚本既可以使用c/lkp-tests目录下已存在的，也可自己编写并分别添加到上述两个目录下。

2. [编写PKGBUILD](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/write-PKGBUILD.zh.md)（无法通过命令安装的软件如yum install/apt-get add，才需要编写PKGBUILD，可以直接安装的情况下请跳过该步骤）
	在/c/lkp-tests/pkg目录下创建与测试用例同名文件夹，并编辑PKGBUILD文件。此文直接使用已存在的PKGBUILD文件
   	```
   	ls /c/lkp-tests/pkg/sysbench-cpu/PKGBUILD
	```
   	使用cci-makepkg.yaml根据编写好的PKGBUILD文件生成latest.cgz包
   	```
   	submit -m cci-makepkg.yaml cci-makepkg.benchmark=sysbench-cpu
   	ls /srv/initrd/pkg/container/centos/aarch64/7/sysbench-cpu/latest.cgz
   	#如遇访问github 443的网络问题，可将PKGBUILD文件中的source值替换为fork github仓库后的gitee地址
   	```

3. 使用cci-depends.yaml生成执行测试任务sysbench-cpu所需的依赖包
	在/c/lkp-tests/distro/depends目录下编辑同名文件sysbench-cpu，并写入依赖的软件名

   	```
   	cat > /c/lkp-tests/distro/depends/sysbench-cpu << EOF
   	libmariadb3
   	EOF
   	```
   	使用cci-depends.yaml根据编写好的sysbench-cpu文件生成latest.cgz包
   	```
  	submit -m cci-depends.yaml cci-depends.benchmark=sysbench-cpu
   	ls /srv/initrd/deps/container/centos/aarch64/7/sysbench-cpu/sysbench-cpu.cgz
   	```

	> **说明：**           
	> 每次修改完/c/lkp-tests目录下的文件之后，要将变动应用到下一次的job任务中，需要手动执行`sh /c/compass-ci/container/lkp-initrd/run`文件才能生效

4. 添加待测试仓库 URL 到 upstream仓库
	在/c/git-repos/upstream仓库下创建目录，一级目录为待测试仓库名的首字母"s"，二级目录为待测试仓库名称"sysbench"，并编辑与待测试仓库同名文件”sysbench“，将你的待测试仓库以如下格式写入该文件。
   	```
   	mkdir -p /c/git-repos/upstream/s/sysbench/
   	cat > /c/git-repos/upstream/s/sysbench/sysbench << EOF
   	url:
   	- https://gitee.com/liu-yinsi/sysbench
   	EOF
   	```

	配置 upstream仓库中的DEFAULTS文件，提交测试任务
	自动提交sysbench-cpu.yaml任务，指定测试机为dc-8g的docker测试机，指定测试机系统os=openeuler ，os_version=20.03-pre，os_arch=aarch64，submit参数可根据需要参考如下格式填写。

	```
   	cat > /c/git-repos/upstream/s/sysbench/DEFAULTS << EOF
   	submit:
   	- command: testbox=dc-8g os=centos os_version=7 os_arch=aarch64 os_mount=container docker_image=centos:7 sysbench-cpu.yaml
   	EOF
   	```

	> **说明：**      
   	> [os /os_version /os_arch](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/job/os-os_verison-os_arch.md) [os_mount](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/job/os_mount.md)
	> [job](https://gitee.com/wu_fengguang/compass-ci/tree/master/doc/job)
	
5. 重启git-mirror服务
	```
	cd /c/compass-ci/container/git-mirror
	./start
	```
	
	> **说明：**    
	> 私有测试仓库需要修改/c/compass-ci/container/git-mirror/Dockerfile文件，将~/.ssh文件夹拷贝到容器/home/lkp/.ssh中（如使用了ssh协议还需要安装openssh），并重新构建镜像后再启动该服务。
	
6. 自动触发测试
	
	通过git push 将修改后的代码合入到待测试仓库[sysbench](https://gitee.com/liu-yinsi/sysbench)中，即可自动触发对待测试仓库的测试。
	
7. 实时查看测试任务执行状态
	
	```
	docker logs -f sub-fluentd| grep auto-submit
	```
	
	通过查看auto-submit日志，可以看到打印submit /c/lkp-tests/jobs/build-pkg.yaml, got job id=nolab.2，nolab.2就是自动触发提交的job id。
	
8. 查看提交任务的结果
	
	根据job id查看任务状态和任务详细输出结果(将命令中的nolab.2替换成上一步骤中打印的job id)。
	
	```
	es-find id=nolab.2 | grep job_state
	result_root=$(es-find id=nolab.2 | grep "result_root" | cut -d'"' -f4)
	cd /srv/$result_root
	ls
	tail output
	```
	
	> **说明：**    
	> 任务结果文件生成需要等待约1分钟，可多次使用上述ls命令查看
