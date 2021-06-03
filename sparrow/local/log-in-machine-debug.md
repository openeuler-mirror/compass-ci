# 调测环境登录
1. 登录测试机
	对于测试失败的任务，通过使用output文件同级目录下的job.yaml，以及/c/lkp-tests/jobs/ssh-on-fail.yaml，可以自动登录到测试机中复现失败的任务场景。
	```
	submit -m -c job.yaml --include ssh-on-fail.yaml
	```
	
	> **说明：**    
	> submit任务提交工具的参数 --include的作用是将“--include”参数后面的yaml文件合并进整个执行任务的yaml文件中，这里选择ssh-on-fail.yaml就会将ssh-on-fail.yaml文件中的一些参数合并进前面的job.yaml文件中（如果前后两个文件出现相同的参数，后面文件的参数将会覆盖前面的参数）；参数“-m”用于监控任务执行状态；参数“-c”用于自动登录到测试机。
	
2. 进入测试机环境之后，可通过查看测试机中/tmp/lkp目录下的output文件，即可见复现的测试结果并调试
	```
	tail -f /tmp/lkp/output
	```
	
	执行exit即可退出测试机。
