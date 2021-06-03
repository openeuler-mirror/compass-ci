# borrow一台测试机
	
1. 生成依赖包sshd.cgz
	borrow一台docker测试机需要依赖包sshd.cgz，可以使用[submit命令](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/submit-job.zh.md)先提交cci-depends任务，在/srv/initrd/deps/container/centos/aarch64/7/sshd目录下生成依赖包sshd.cgz，如果该目录下sshd.cgz包已存在则跳过该步骤。
	```
	submit -m cci-depends.yaml cci-depends.benchmark=sshd
	```
	
2. [borrow测试机](https://gitee.com/openeuler/compass-ci/blob/master/doc/manual/borrow-machine.zh.md)（本地搭建用户请忽略该文档中的“前置准备“部分的内容）
