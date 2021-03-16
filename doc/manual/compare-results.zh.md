# 比较功能介绍
  比较功能用于分析不同任务的结果，显示不同影响因素下的性能波动和变化，供用户分析性能影响因素。

## url: https://compass-ci.openeuler.org/compare

## 选项说明
### 过滤器:
    - suite: iperf, netperf, mysql, ...
    - OS: openeuler 20.03, centos 7.6, ...
    - os_arch: aarch64, x86
    - tbox_group: vm-2p8g, taishan200-2880-2s48p-256g, ...
    我们可以任意组合以上选项来限制比较范围，但至少选择一个选项作为过滤器。

### 维度
    可选维度: os, os_version, os_arch, suite, tbox_group.
    在过滤器中，我们将按所选维度比较所有不同的任务结果，并保持其他测试条件一致。

## 示例:
    过滤器: suite = iperf
    维度: os_version

    结果:
	os=openeuler/os_arch=aarch64/pp.iperf.protocol=tcp/pp.iperf.runtime=20/tbox_group=vm-2p8g  # 其他测试条件一致


	               20.09                           20.03  metric
	--------------------  ------------------------------  ------------------------------
	      fails:runs        change        fails:runs
	           |               |               |
	          3:3          -100.0%            0:3         last_state.exit_fail
	          3:3          -100.0%            0:3         last_state.is_incomplete_run
	          3:3          -100.0%            0:3         last_state.test.iperf.exit_code.127
	          3:3          -100.0%            0:3         stderr.perf_command_failed



	               20.09                           20.03  metric
	--------------------  ------------------------------  ------------------------------
	          %stddev       change            %stddev
	             \             |                 \
	4.461021e+10 ±  6%      -17.4%    3.686392e+10 ± 12%  iperf.tcp.receiver.bps
	4.461112e+10 ±  6%      -17.4%    3.686935e+10 ± 12%  iperf.tcp.sender.bps
	       94.82            -44.0%           53.10        boot-time.boot
	      123.11            -58.4%           51.19        boot-time.idle
	        0.00               0              4.87        boot-time.kernel_boot
	     4165.50 ± 12%      -99.9%            5.00        interrupts.38:GICv3.36.Level.virtio0
