# web页面
1. 配置web服务并运行
	```
	server_ip=$(curl -sS ip.sb)
	echo $server_ip
	git clone https://gitee.com/theprocess/crystal-ci.git /c/crystal-ci
	sed -i "s/^export const BASEURLRESULT = '.*/export const BASEURLRESULT = 'http:\/\/$server_ip:20007';/g" /c/crystal-ci/src/utils/baseUrl.js
	sed -i "s/^const BASEURL = '.*/const BASEURL = 'http:\/\/$server_ip:20003';/g" /c/crystal-ci/src/utils/axios.utils.js
	cd /c/crystal-ci
	./build
	./start
	```
	
	在浏览器上打开Compass-CI web页面http://server_ip:11302/jobs，确认web服务启动成功（将server_ip替换为curl -sS ip.sb命令中打印出来的ip地址）。所有的测试结果，用户都可以在web页面查看
	
	在搜索框输入sysbench，即可查看该待测试仓库的任务结果。
