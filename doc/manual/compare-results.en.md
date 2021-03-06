# How Do I Compare Test Results?
The Compare feature is used to analyze the results of different jobs, show the performance waves and changes under different influencing factors, for users to analyze performance influencing factor.

## url: https://compass-ci.openeuler.org/compare

## options directions
### filters:
    - suite: iperf, netperf, mysql, ...
    - OS: openeuler 20.03, centos 7.6, ...
    - os_arch: aarch64, x86
    - tbox_group: vm-2p8g, taishan200-2880-2s48p-256g, ...
    we can combine the above options arbitrarily to limit compare scope.
    choose at least one option as filter.

### dimension
    Dimension can select: os, os_version, os_arch, suite, tbox_group.
    Within filter, we will compare all different job result by dimension
    and keep other test conditions are same.

## example:
    filter: suite = iperf
    dimension: os_version

    result:
    os=openeuler/os_arch=aarch64/pp.iperf.protocol=tcp/pp.iperf.runtime=20/tbox_group=vm-2p8g  # other test conditions keep same


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
