# 本地搭建 compass-ci 服务器节点

在 openEuler 系统一键部署 compass-ci 环境，当前已支持 openEuler-aarch64-20.03-LTS 系统环境，以下配置仅供参考。

>**说明：**
>本文只适用于在较为干净的openEuler系统一键部署compass-ci环境，如果您的环境中有如下设置，将无法成功部署：
>1.lkp用户UID不是1090（如果没有该用户请忽略）
>2.运行了Kubernetes（compass-ci需要使用docker，而非podman-docker，且compass-ci需要占用很多服务端口，例如es， redis， rabbitmq等，易与当前环境中已使用的端口冲突）

## 准备工作
- 硬件
	服务器类型：ThaiShan200-2280 (建议)
	架构：aarch64
	内存：>= 64GB
	CPU：64 nuclear (建议)
	硬盘：>= 500G (建议为/srv/目录划分独立分区; 对大型部署，为/srv/下的子目录划分单独分区)

	>**以下方案仅供参考，请酌情修改后使用：**
	>[划分较小独立分区](https://gitee.com/openeuler/compass-ci/blob/master/sparrow/1-storage/small)
	>[划分较大独立分区](https://gitee.com/openeuler/compass-ci/blob/master/sparrow/1-storage/large)

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

2. 设置文件权限
	```bash
	umask 002
	```

	>**说明：**
	>umask 002 只是暂时设置umask值，需要修改/etc/bashrc中的umask值为002才能长期有效
	>执行下个步骤前请确保当前umask值为002，否则因文件权限问题将导致部分服务无法正常运行。

3. 创建工作目录并克隆 compass-ci和lkp-tests项目代码，并使用指定的commit id
	```bash
	mkdir -p /c/
	git clone https://gitee.com/openeuler/compass-ci.git /c/compass-ci
	git clone https://gitee.com/compass-ci/lkp-tests.git /c/lkp-tests
	cd /c/compass-ci
	git reset --hard 82fa77d62cc40a72db5dfa3617c9a50f963b8fa4
	cd /c/lkp-tests
	git reset --hard 1d8d8f5ea2c4a3b8fd5d7dd0c845f2a5fc929c41
	```
	>**说明：**
	>该版本已经过验证，可以正常进行部署。

4. 编辑setup.yaml配置用户名和邮箱
	```bash
	vi /c/compass-ci/sparrow/setup.yaml
	```

	>**说明：**
	>只需填写my_account, my_name, my_email, 且my_account, my_name, my_email冒号后面必须有1个空格。

5. 执行一键部署脚本 install-tiny
	```bash
	export skip_build_image=true
	cd /c/compass-ci/sparrow && ./install-tiny
	```
	skip_build_image=true表示除了少数几个容器(例如es, logging-es, dnsmasq)必须在用户本地通过Dockerfile构建出来以外，其他镜像是不需要本地构建的，
	部署脚本将直接从[此处](https://repo.oepkgs.net/openEuler/compass-ci/cci-deps/docker)下载镜像tar包使用，以解决本地构建镜像耗时，且网络不稳定易造成构建失败的问题。

6. 注册账号
	- 使环境变量生效
	```bash
	source /etc/profile.d/compass.sh
	```
	非root用户注册帐号，该用户登录系统后直接使用build-my-info命令注册。
	```bash
	build-my-info -e $my_email -n $my_name -a $my_account
	```

#### 提交测试任务
本文以/c/lkp-tests/jobs/目录下已有的通用测试用例host-info.yaml为例
- 使用[submit命令](https://gitee.com/openeuler/compass-ci/blob/master/doc/job/submit/submit-job.zh.md)提交测试用例
	```bash
	submit host-info.yaml
	```

	执行上述命令会打印提示信息如下:
	```
	submit_id=bf5e7ad7-839d-48ec-a033-23281323c750
	submit /c/lkp-tests/jobs/host-info.yaml, got job id=nolab.1
	```

- 查看任务结果
等待约1分钟，可根据上一步骤中打印的job id查看任务结果。
	```bash
	cd $(es-find id=nolab.1 |grep result_root|awk -F '"' '{print "/srv/"$4}') && ls
	```

	结果文件介绍
	job.yaml文件
	job.yaml 文件中部分字段是用户提交上来的，其他字段是平台根据提交的 job 自动添加进来的。此文件包含了测试任务需要的所有参数。

	output文件
	output 文件记录了用例的执行过程，文件最后部分一般会有 check_exit_code 这个状态码，非 0 代表测试用例错误。

	stats.json
	测试用例执行完成会生成一个与测试用例同名的文件，记录它们的测试命令及标准化输出结果。compass-ci 会对这些文件进行解析，生成后缀名是 .json 的文件。
	stats.json 是所有的 json 文件的汇总，所有测试命令的关键结果都会统计到这个文件中，便于后续的比较和分析。

体验更多功能
- [自动化测试](https://gitee.com/openeuler/compass-ci/blob/master/sparrow/local/test-oss-project.md)
- [调测环境登录](https://gitee.com/openeuler/compass-ci/blob/master/sparrow/local/log-in-machine-debug.md)
- [测试结果分析](https://gitee.com/openeuler/compass-ci/blob/master/sparrow/local/compare-results.md)
- [borrow测试机](https://gitee.com/openeuler/compass-ci/blob/master/sparrow/local/borrow-machine.md)
- [web页面](https://gitee.com/openeuler/compass-ci/blob/master/sparrow/local/web.md)
