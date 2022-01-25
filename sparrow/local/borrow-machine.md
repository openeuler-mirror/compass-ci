# borrow一台测试机
	
1. 生成依赖包sshd.cgz
	borrow一台docker测试机需要依赖包sshd.cgz，可以使用[submit命令](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/job/submit/submit-job.zh.md)先提交cci-depends任务，在/srv/initrd/deps/container/centos/aarch64/7/sshd目录下生成依赖包sshd.cgz，如果该目录下sshd.cgz包已存在则跳过该步骤。
	```
	submit -m cci-depends.yaml cci-depends.benchmark=sshd
	```
	
2. 生成本地公钥

	使用下面命令查看是否已存在ssh公钥：
	```
	ls ~/.ssh/*.pub
	```

	如果当前没有现成的公钥，请使用下面命令进行生成：
	```
	ssh-keygen
	```

3. 借一台本地的容器测试机
	```
	submit -c -m testbox=dc-8g borrow-1h.yaml
	等待约一分钟，将自动登录到容器测试机中
	```
	如果是在物理机部署compass-ci，还可以借到qemu测试机，将testbox值替换为vm-2p8g即可。
