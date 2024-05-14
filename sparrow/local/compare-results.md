# 比较结果
1. 提交基于不同os环境下的性能测试任务（以iperf为例）
	分别在centos：7和 openEuler：20.03的os 环境中执行iperf任务，生成用于结果分析的样例。
	在centos：7的docker测试机中执行iperf任务需要生成依赖包iperf.cgz，后续再在该环境下提交iperf任务时无需重复执行该步骤。
	```
	submit -m cci-depends.yaml cci-depends.benchmark=iperf
	```
	
2. 编辑os-matrix-dc.yaml，指定使用centos：7和 [openEuler：20.03-pre](https://api.compass-ci.openeuler.org:20008/initrd/dockerimage/openeuler-pre.tar)（由于dockerhub没有openeuler20.03的镜像，可以下载该链接并使用docker load -i openeuler-pre.tar加载到本地），如需要使用其他os，参考如下文件格式修改即可。
	```
	cat > /c/lkp-tests/jobs/os-matrix-dc.yaml << EOF
	os_arch: aarch64
	os_mount: container
	testbox: dc-8g
	
	os | os_version | docker_image:
	- centos    | 7     | centos:7
	- openeuler | 20.03 | openeuler:20.03-pre
	EOF
	```
	
3. 编辑iperf.yaml
	```
	cat > /c/lkp-tests/jobs/iperf.yaml << EOF
	suite: iperf
	testcase: iperf
	category: benchmark
	
	runtime: 300s
	
	cluster: cs-localhost
	
	if role server:
	  iperf-server:
	
	if role client:
	  iperf:
	    protocol:
	    - tcp
	EOF
	```
	
4. 提交任务，加上参数--include os-matrix-dc.yaml
	```
	submit -m iperf.yaml --include os-matrix-dc.yaml
	```
	
5. 比较不同os环境下的基准性能测试iperf的结果
	```
	compare suite=iperf -d os |grep -C 5 bps
	```
	
	> **说明：**       
	> 参数 “-d”表示基于某个维度进行比较，这里表示基于os维度进行比较，也可以根据其他维度（os_version, os_arch, suite, tbox_group）来比较。
	> 参数"suite=iperf"表示指定suite=iperf的job才会进行比较，作为过滤器来限制比较范围。
	> bps指的是bytes per second，可以看出不同os上的iperf性能测试无论是平均值还是方差都有明显差异。
	> [比较功能介绍](https://gitee.com/openeuler/compass-ci/blob/master/doc/result/compare-results.zh.md)
