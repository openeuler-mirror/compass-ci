# deploy multi-qemu/multi-docker

用于在物理机服务器上部署multi-qemu/multi-docker

## multi-qemu/multi-docker新特性说明

multi-qemu/multi-docker自动适配job请求所需的计算机规格启动测试机；
无需再为不同规格的测试机单独启动multi-qemu/multi-docker服务;
单进程请求job；
使用 -p 参数，允许multi-qemu/multi-docker自动计算最大测试机数量；

## 使用命令运行multi-qemu/multi-docker

	multi-qemu:

		指定最大测试机数量：

			/compass-ci/providers/multi-qemu -n ${name} -c ${num} -q ${queue}

		自动计算最大测试机数：

			/compass-ci/providers/multi-qemu -n ${name} -p -q ${queue}

	multi-docker:

		指定最大测试机数量：

			/compass-ci/providers/multi-docker -n ${name} -c ${num} -q ${queue}

		自动计算最大测试机数：

			/compass-ci/providers/multi-docker -n ${name} -p -q ${queue}

## 提交job运行multi-qemu/multi-docker

job.yaml:

	multi-qemu.yaml:

		'''
		suite: multi-qemu
		category: functional
		swap:
		simplify-ci:
		runtime: 100d
		os: openeuler
		os_version: 22.03-LTS
		os_mount: local

		multi-qemu:
		        nr_vm: 0
		sleep:
		'''

	multi-docker.yaml:

		'''
		suite: multi-docker
		category: functional
		swap:
		simplify-ci:
		runtime: 100d
		os: openeuler
		os_version: 22.03-LTS
		os_mount: local

		multi-docker:
		        nr_container: 0
		sleep:
		'''

在提交multi-qemu/multi-docker的job时，如果设置下面字段：

	- nr_vm
	- nr_container

当值为0时，自动计算测试机数量；
当值为非0时，指定最大测试机数量；

multi-qemu/multi-docker自动计算测试机数量方式稍有差异，

	mult-qemu：

		基准：vm-2p4g

	multi-docker:

		基准: dc-4g

## 验证

验证单实例请求job：

	登录测试机，查看对应进程数验证是否为单实例：

		multi-qemu:

			ps -ef | grep qemu.rb

		multi_docker:

			ps -ef | grep docker.rb

验证自动适配测试机规格，borrow机器为例；

	提交不同测试机规格的任务，测试机运行起来后，验证测试机规格：

		multi-qemu：

			登入测试机，查看文件：

				/proc/meminfo
				/proc/cpuinfo

			查看测试机资源

		multi-docker：

			在宿主机上，使用命令：

				docker inspect ${job_id} | grep Memory

			查看分配的内存资源。

验证自动计算最大测试机数量：

	提交multi-qemu/multi-dockerjob时，下面字段：

		- nr_vm
		- nr_container

	分别指定0值和非0值，job运行后，查看文件：

		/tmp/${HOSTNAME}/specmeminfo.yaml

	文件，其中的：

		- vms
		- containers

	所对应的数字即为可分配的数字后缀；
	最大值即为最大可运行的测试机数量。
