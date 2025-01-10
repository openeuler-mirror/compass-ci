# 1.需求描述 
在compass-ci + lkp-tests测试框架支持的软件包测试任务(job)中，有些job需要依赖对应的软件包版本，
如对应commit id + 对应编译配置文件构建出的特定软件包，因此需要在测试框架中定义一种依赖传递机制，以支持该需求。

# 2.相关设计与实现
在compass-ci中为job定义了ss key字段以支持软件包依赖传递机制(auto_depend)，ss全称是Software Stack，即类比软件栈概念来描述软件包的依赖关系。
ss key字段定义在compass-ci代码src/lib/job.cr中。ss字段的使用可参考src/scheduler/auto_depend_submit_job.cr及src/scheduler/plugins/pkgbuild.cr
使用时可在相应job.yaml中指定ss字段，并在其下指定所依赖软件包的相关参数，如软件包版本commit,编译配置文件config等，
测试框架在处理该job时就会识别ss字段，并结合ss字段下指定的依赖软件包参数，提供该依赖软件包(如寻找到现成的软件包版本或构建出依赖的软件包)。

## ss 软件包依赖(auto_depend)处理流程设计：

```
伪代码 设计: # xxx is the actually implementation currently in compass-ci.
submit_job() # refer to src/scheduler/auto_depend_submit_job.cr
	for each job
		handle_job(job) # src/scheduler/plugins/pkgbuild.cr
		if job.ss key existed # ss == Software Stack, refer to src/lib/job.cr
			for each package in ss
				get_pkgbuild_params from ss key/values # like software repo_name,upstream_commit,upstream_url,config file, refer to init_pkgbuild_params
				if pkgbuild cgz file already existed # for example in /srv/initrd/build-pkg/container/openeuler/aarch64/20.03/xxx/yyy.cgz
					skip submit_pkgbuild_job
				if pkg_name == "linux"
					update/record_kernel_uri # tell the waiting job where to find linux build result(like vmlinuz and modules.cgz) later, although the build hasn't started currently
				                         # where to find linux build result: for example http://172.168.131.113:8800/kernel/aarch64/openeuler_defconfig/commit
				submit_pkgbuild_job for this package # create job.yaml and run LKP_SRC/sbin/submit job.yaml
				init pkgbuild_job_status to polling # init ss_wait_jobs status hash, key = pkgbuild job id, value initialized to unknown(meaning running and unfinished). add job.waited hash = {job.id => "job_health"} but not used; 
			end_for_each_package
		handle_job remaining steps
	end_for_each_job		

close_job() # src/scheduler/close_job.cr, pkgbuild job finished
	if job finished success 
		pkgbuild_job_status = success # update_wait_job_by_ss(job), update ss_wait_jobs status hash(value change from unknown to success): pkgbuild_job.id => success
		
Scheduler pick_next_job from runqueue # src/lib/init_ready_queues.cr, InitReadyQueues.instance.loop_init() loop every 10s
	for each testbox_type # tbox_type maybe docker, vm, hw
		query_and_sort_jobs_running_with_specific_condition # get_submit_jobs() matched job_state == submit && job_health not existed && has_key = ss_wait_jobs
				if (queried_job.pkgbuild_job_status flag existed) # get_submit_jobs.job.has_key?("ss_wait_jobs")
					if (pkgbuild_job_status == success) # filter_by_ss() check ss_wait_jobs.values == success ?
						put the pending job to runqueue # get_submit_jobs._aggs[key] << val["_source"], waiting for schedule(no need to run immediately after the pkgbuild job)
		schedule_job_to_run_in_tboxs # g_arch_jobs.each init_ready_queues
	end_for_each_tbox_type
```

## 相关代码
相关commmit：
https://gitee.com/openeuler/compass-ci/commit/400cdf850e19f
https://gitee.com/openeuler/compass-ci/commit/b00e4111e007b
https://gitee.com/openeuler/compass-ci/commit/2004ac0c46724


# 3.相关应用
compass-ci + lkp-tests测试框架需支持软件包版本的构建缺陷，功能缺陷，性能回退等问题的二分查找(bisect)定界定位, 
可以使用job的ss字段指定使用对应commit的软件包进行功能和性能测试，根据测试结果在git log中迭代搜寻引入问题的commit id,
以支持软件包的功能及性能问题bisect定位。

如下以linux kernel host-info功能测试为例说明ss字段相关应用。

## 示例：  
基于linux v5.10测试host-info功能，对应job提交命令： submit test.yaml

```
#! test.yaml
suite: host-info
testbox: vm-2p8g
os: openeuler
os_version: 22.03-lts-sp4
os_arch: aarch64
host-info:
ss: # Software Stack
  linux:
    fork: linux-next
    commit: v5.10
    config: /srv/cci/build-config/linux/openeuler_defconfig_arm64
    _upstream_url: https://mirrors.tuna.tsinghua.edu.cn/git/linux-next.git
    _upstream_dir: upstream
    _pkgbuild_source: https://git.archlinux.org/linux.git
    pkg_ver: v1
    testbox: dc-32g
```

## 验证情况
10s为周期轮询等待ss_wait_jobs状态从unknown变为sucess

```
"-------------------------update_wait_job_by_ss---------------------"
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:36.617+0800","message":"set job content, account: zzk"}
" send_mq_msg1"
" job_stage:  boot"
" send_mq_msg2"
" deadline: , state: requesting"
" send_mq_msg3 {\"job_id\" => \"\", \"testbox\" => \"local-taishan200-2280-2s64p-128g--a108-1\", \"deadline\" => \"\", \"time\" => \"2025-01-03T21:02:37+0800\", \"job_stage\" => \"boot\"}"
" send_mq_msg1"
" job_stage:  boot"
" send_mq_msg2"
" deadline: , state: requesting"
" send_mq_msg3 {\"job_id\" => \"\", \"testbox\" => \"local-taishan200-2280-2s64p-128g--a108-1\", \"deadline\" => \"\", \"time\" => \"2025-01-03T21:02:37+0800\", \"job_stage\" => \"boot\"}"
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:37.104+0800","message":"get job boot content","status_code":101,"method":"GET","resource":"/ws/boot.ipxe?mac=0a-ba-80-43-4f-88&hostname=taishan200-2280-2s64p-128g--a108-1&left_mem=115&tbox_type=vm&is_remote=false","testbox":"local-taishan200-2280-2s64p-128g--a108-1"}
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:37.104+0800","message":"qemu get job from ready queues by host_machine: local-taishan200-2280-2s64p-128g--a108","status_code":101,"method":"GET","resource":"/ws/boot.ipxe?mac=0a-ba-80-43-4f-88&hostname=taishan200-2280-2s64p-128g--a108-1&left_mem=115&tbox_type=vm&is_remote=false","testbox":"local-taishan200-2280-2s64p-128g--a108-1"}
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:37.106+0800","from":"172.17.0.1:48166","message":"socket on closed","status_code":101,"method":"GET","resource":"/ws/boot.ipxe?mac=0a-ba-80-43-4f-88&hostname=taishan200-2280-2s64p-128g--a108-1&left_mem=115&tbox_type=vm&is_remote=false","testbox":"local-taishan200-2280-2s64p-128g--a108-1"}
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:37.574+0800","message":"timing init ready_queues"}
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:37.574+0800","message":"init_common_tbox_from_redis [\"/tbox/dc/local-taishan200-2280-2s48p-256g--a1004\", \"/tbox/hw/taishan200-2280-2s48p-512g--a1008\", \"/tbox/vm/local-taishan200-2280-2s64p-128g--a108\"]"}
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:37.575+0800","message":"all tboxs {\"dc\" => {\"local-taishan200-2280-2s48p-256g--a1004\" => {\"type\" => \"dc\", \"arch\" => \"aarch64\", \"owner\" => \"local\", \"max_mem\" => \"250\", \"hostname\" => \"local-taishan200-2280-2s48p-256g--a1004\", \"is_remote\" => \"false\"}}, \"vm\" => {\"local-taishan200-2280-2s64p-128g--a108\" => {\"type\" => \"vm\", \"arch\" => \"aarch64\", \"owner\" => \"local\", \"max_mem\" => \"124\", \"hostname\" => \"local-taishan200-2280-2s64p-128g--a108\", \"is_remote\" => \"false\"}}, \"hw\" => {\"taishan200-2280-2s48p-512g--a1008\" => {\"type\" => \"hw\", \"hostname\" => \"taishan200-2280-2s48p-512g--a1008\", \"arch\" => \"aarch64\", \"max_mem\" => \"512\"}}}"}
"======================tmp_source=========================="
{"ss_wait_jobs" => {"10250103201504067" => "unknown"},
 "os_arch" => "aarch64",
 "my_account" => "zzk",
 "id" => "10250103201457065",
 "memory_minimum" => "8"}
"filter_by_ss----------------------"
{"10250103201504067" => "unknown"}
zzk dbg bef ret [{"arch" => "aarch64", "jobs" => {"zzk" => []}}] itemarch {"arch" => "aarch64", "jobs" => {"zzk" => []}}
{"dc" => {}, "vm" => {}, "hw" => {}}
"10250103201504067 send_mq_msg1"
"10250103201504067 job_stage:  finish"
"10250103201504067 send_mq_msg2"
"10250103201504067 deadline: 2025-01-03T21:22:35+0800, state: "
"10250103201504067 send_mq_msg3 {\"job_id\" => \"10250103201504067\", \"testbox\" => \"\", \"deadline\" => \"2025-01-03T21:22:35+0800\", \"time\" => \"2025-01-03T21:02:38+0800\", \"job_stage\" => \"finish\"}"
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:38.122+0800","message":"set job content, account: compass-ci"}
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:38.128+0800","message":"scheduler update job to id2job 10250103201504067: Etcd::Model::PutResponse(@header=Etcd::Model::Header(@cluster_id=14841639068965178418, @member_id=10276657743932975437, @revision=6319898, @raft_term=20), @prev_kv=nil)","status_code":200,"method":"GET","resource":"/~lkp/cgi-bin/lkp-post-run?job_file=/lkp/scheduled/job.yaml&job_id=10250103201504067&mem=18&cpu=4","job_id":"10250103201504067","api":"lkp-post-run","elapsed_time":2948.716281,"elapsed":"2948.72ms"}
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:38.419+0800","message":"move in_process to extract in_process: /queues/sched/in_process/local-taishan200-2280-2s48p-256g--a1004/10250103201504067, extract: extract_stats/10250103201504067, ret: true","status_code":200,"method":"GET","resource":"/~lkp/cgi-bin/lkp-post-run?job_file=/lkp/scheduled/job.yaml&job_id=10250103201504067&mem=18&cpu=4","job_id":"10250103201504067","api":"lkp-post-run","elapsed_time":3681.169045,"elapsed":"3681.17ms"}
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:38.419+0800","message":"scheduler move in_process to extract_stats 10250103201504067: true","status_code":200,"method":"GET","resource":"/~lkp/cgi-bin/lkp-post-run?job_file=/lkp/scheduled/job.yaml&job_id=10250103201504067&mem=18&cpu=4","job_id":"10250103201504067","api":"lkp-post-run","elapsed_time":3681.51505,"elapsed":"3681.52ms"}
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:38.419+0800","from":"172.17.0.1:48126","message":"access_record","status_code":200,"method":"GET","resource":"/~lkp/cgi-bin/lkp-post-run?job_file=/lkp/scheduled/job.yaml&job_id=10250103201504067&mem=18&cpu=4","job_id":"10250103201504067","api":"lkp-post-run","elapsed_time":3681.660383,"elapsed":"3681.66ms"}
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:40.258+0800","message":"GetJob.new.get_job_by_tbox_type taishan200-2280-2s48p-512g--a1008, hw, return: ","status_code":200,"method":"GET","resource":"/boot.ipxe/mac/44-67-47-85-d5-48","testbox":"taishan200-2280-2s48p-512g--a1008","api":"boot","elapsed_time":530461.903324,"elapsed":"530461.9ms"}
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:40.935+0800","from":"172.17.0.1:48258","message":"access_record","status_code":200,"method":"GET","resource":"/heart-beat?hostname=taishan200-2280-2s64p-128g--a108&type=vm&is_remote=false","api":"heart-beat","elapsed_time":337.339274,"elapsed":"337.34ms"}
" send_mq_msg1"
" job_stage:  boot"
" send_mq_msg2"
" deadline: , state: requesting"
" send_mq_msg3 {\"job_id\" => \"\", \"testbox\" => \"local-taishan200-2280-2s48p-256g--a1004-2\", \"deadline\" => \"\", \"time\" => \"2025-01-03T21:02:42+0800\", \"job_stage\" => \"boot\"}"
" send_mq_msg1"
" job_stage:  boot"
" send_mq_msg2"
" deadline: , state: requesting"
" send_mq_msg3 {\"job_id\" => \"\", \"testbox\" => \"local-taishan200-2280-2s48p-256g--a1004-2\", \"deadline\" => \"\", \"time\" => \"2025-01-03T21:02:42+0800\", \"job_stage\" => \"boot\"}"
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:42.106+0800","message":"get job boot content","status_code":101,"method":"GET","resource":"/ws/boot.container?hostname=taishan200-2280-2s48p-256g--a1004-2&left_mem=218&tbox_type=dc&is_remote=false","testbox":"local-taishan200-2280-2s48p-256g--a1004-2"}
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:42.106+0800","message":"container get job from ready queues by host_machine: local-taishan200-2280-2s48p-256g--a1004","status_code":101,"method":"GET","resource":"/ws/boot.container?hostname=taishan200-2280-2s48p-256g--a1004-2&left_mem=218&tbox_type=dc&is_remote=false","testbox":"local-taishan200-2280-2s48p-256g--a1004-2"}
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:42.108+0800","from":"172.17.0.1:48282","message":"socket on closed","status_code":101,"method":"GET","resource":"/ws/boot.container?hostname=taishan200-2280-2s48p-256g--a1004-2&left_mem=218&tbox_type=dc&is_remote=false","testbox":"local-taishan200-2280-2s48p-256g--a1004-2"}
" send_mq_msg1"
" job_stage:  boot"
" send_mq_msg2"
" deadline: , state: requesting"
" send_mq_msg3 {\"job_id\" => \"\", \"testbox\" => \"local-taishan200-2280-2s64p-128g--a108-1\", \"deadline\" => \"\", \"time\" => \"2025-01-03T21:02:47+0800\", \"job_stage\" => \"boot\"}"
" send_mq_msg1"
" job_stage:  boot"
" send_mq_msg2"
" deadline: , state: requesting"
" send_mq_msg3 {\"job_id\" => \"\", \"testbox\" => \"local-taishan200-2280-2s64p-128g--a108-1\", \"deadline\" => \"\", \"time\" => \"2025-01-03T21:02:47+0800\", \"job_stage\" => \"boot\"}"
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:47.135+0800","message":"get job boot content","status_code":101,"method":"GET","resource":"/ws/boot.ipxe?mac=0a-ba-80-43-4f-88&hostname=taishan200-2280-2s64p-128g--a108-1&left_mem=115&tbox_type=vm&is_remote=false","testbox":"local-taishan200-2280-2s64p-128g--a108-1"}
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:47.135+0800","message":"qemu get job from ready queues by host_machine: local-taishan200-2280-2s64p-128g--a108","status_code":101,"method":"GET","resource":"/ws/boot.ipxe?mac=0a-ba-80-43-4f-88&hostname=taishan200-2280-2s64p-128g--a108-1&left_mem=115&tbox_type=vm&is_remote=false","testbox":"local-taishan200-2280-2s64p-128g--a108-1"}
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:47.137+0800","from":"172.17.0.1:48376","message":"socket on closed","status_code":101,"method":"GET","resource":"/ws/boot.ipxe?mac=0a-ba-80-43-4f-88&hostname=taishan200-2280-2s64p-128g--a108-1&left_mem=115&tbox_type=vm&is_remote=false","testbox":"local-taishan200-2280-2s64p-128g--a108-1"}
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:48.085+0800","message":"timing init ready_queues"}
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:48.086+0800","message":"init_common_tbox_from_redis [\"/tbox/dc/local-taishan200-2280-2s48p-256g--a1004\", \"/tbox/hw/taishan200-2280-2s48p-512g--a1008\", \"/tbox/vm/local-taishan200-2280-2s64p-128g--a108\"]"}
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:48.086+0800","message":"all tboxs {\"dc\" => {\"local-taishan200-2280-2s48p-256g--a1004\" => {\"type\" => \"dc\", \"arch\" => \"aarch64\", \"owner\" => \"local\", \"max_mem\" => \"250\", \"hostname\" => \"local-taishan200-2280-2s48p-256g--a1004\", \"is_remote\" => \"false\"}}, \"vm\" => {\"local-taishan200-2280-2s64p-128g--a108\" => {\"type\" => \"vm\", \"arch\" => \"aarch64\", \"owner\" => \"local\", \"max_mem\" => \"124\", \"hostname\" => \"local-taishan200-2280-2s64p-128g--a108\", \"is_remote\" => \"false\"}}, \"hw\" => {\"taishan200-2280-2s48p-512g--a1008\" => {\"type\" => \"hw\", \"hostname\" => \"taishan200-2280-2s48p-512g--a1008\", \"arch\" => \"aarch64\", \"max_mem\" => \"512\"}}}"}
"======================tmp_source=========================="
{"ss_wait_jobs" => {"10250103201504067" => "success"},
 "os_arch" => "aarch64",
 "my_account" => "zzk",
 "id" => "10250103201457065",
 "memory_minimum" => "8"}
"filter_by_ss----------------------"
{"10250103201504067" => "success"}
zzk dbg bef append [], key zzk
zzk dbg aft append [{"ss_wait_jobs" => {"10250103201504067" => "success"}, "os_arch" => "aarch64", "my_account" => "zzk", "id" => "10250103201457065", "memory_minimum" => "8"}], key zzk
zzk dbg bef ret [{"arch" => "aarch64", "jobs" => {"zzk" => [{"ss_wait_jobs" => {"10250103201504067" => "success"}, "os_arch" => "aarch64", "my_account" => "zzk", "id" => "10250103201457065", "memory_minimum" => "8"}]}}] itemarch {"arch" => "aarch64", "jobs" => {"zzk" => [{"ss_wait_jobs" => {"10250103201504067" => "success"}, "os_arch" => "aarch64", "my_account" => "zzk", "id" => "10250103201457065", "memory_minimum" => "8"}]}}
"set_priority_weight----------------------"
"ss_wait_jobs"
{"10250103201504067" => "success"}
"set_priority_weight----------------------"
"os_arch"
"aarch64"
"os_arch"
"aarch64"
"set_priority_weight----------------------"
"my_account"
"zzk"
"my_account"
"zzk"
"set_priority_weight----------------------"
"id"
"10250103201457065"
"id"
"10250103201457065"
"set_priority_weight----------------------"
"memory_minimum"
"8"
"memory_minimum"
"8"
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:48.137+0800","message":"get_best_vm from common_vms"}
{"dc" => {},
 "vm" =>
  {"local-taishan200-2280-2s64p-128g--a108" =>
    [{"os_arch" => "aarch64",
      "my_account" => "zzk",
      "id" => "10250103201457065",
      "memory_minimum" => "8",
      "priority" => "11",
      "weight" => "100"}]},
 "hw" => {}}
" send_mq_msg1"
" job_stage:  boot"
" send_mq_msg2"
" deadline: , state: requesting"
" send_mq_msg3 {\"job_id\" => \"\", \"testbox\" => \"local-taishan200-2280-2s48p-256g--a1004-2\", \"deadline\" => \"\", \"time\" => \"2025-01-03T21:02:49+0800\", \"job_stage\" => \"boot\"}"
" send_mq_msg1"
" job_stage:  boot"
" send_mq_msg2"
" deadline: , state: requesting"
" send_mq_msg3 {\"job_id\" => \"\", \"testbox\" => \"local-taishan200-2280-2s48p-256g--a1004-2\", \"deadline\" => \"\", \"time\" => \"2025-01-03T21:02:49+0800\", \"job_stage\" => \"boot\"}"
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:49.140+0800","message":"get job boot content","status_code":101,"method":"GET","resource":"/ws/boot.container?hostname=taishan200-2280-2s48p-256g--a1004-2&left_mem=218&tbox_type=dc&is_remote=false","testbox":"local-taishan200-2280-2s48p-256g--a1004-2"}
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:49.141+0800","message":"container get job from ready queues by host_machine: local-taishan200-2280-2s48p-256g--a1004","status_code":101,"method":"GET","resource":"/ws/boot.container?hostname=taishan200-2280-2s48p-256g--a1004-2&left_mem=218&tbox_type=dc&is_remote=false","testbox":"local-taishan200-2280-2s48p-256g--a1004-2"}
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:49.143+0800","from":"172.17.0.1:48416","message":"socket on closed","status_code":101,"method":"GET","resource":"/ws/boot.container?hostname=taishan200-2280-2s48p-256g--a1004-2&left_mem=218&tbox_type=dc&is_remote=false","testbox":"local-taishan200-2280-2s48p-256g--a1004-2"}
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:50.263+0800","message":"GetJob.new.get_job_by_tbox_type taishan200-2280-2s48p-512g--a1008, hw, return: ","status_code":200,"method":"GET","resource":"/boot.ipxe/mac/44-67-47-85-d5-48","testbox":"taishan200-2280-2s48p-512g--a1008","api":"boot","elapsed_time":540467.581703,"elapsed":"540467.58ms"}
" send_mq_msg1"
" job_stage:  boot"
" send_mq_msg2"
" deadline: , state: requesting"
" send_mq_msg3 {\"job_id\" => \"\", \"testbox\" => \"local-taishan200-2280-2s48p-256g--a1004-1\", \"deadline\" => \"\", \"time\" => \"2025-01-03T21:02:56+0800\", \"job_stage\" => \"boot\"}"
" send_mq_msg1"
" job_stage:  boot"
" send_mq_msg2"
" deadline: , state: requesting"
" send_mq_msg3 {\"job_id\" => \"\", \"testbox\" => \"local-taishan200-2280-2s48p-256g--a1004-1\", \"deadline\" => \"\", \"time\" => \"2025-01-03T21:02:56+0800\", \"job_stage\" => \"boot\"}"
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:56.176+0800","message":"get job boot content","status_code":101,"method":"GET","resource":"/ws/boot.container?hostname=taishan200-2280-2s48p-256g--a1004-1&left_mem=250&tbox_type=dc&is_remote=false","testbox":"local-taishan200-2280-2s48p-256g--a1004-1"}
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:56.176+0800","message":"container get job from ready queues by host_machine: local-taishan200-2280-2s48p-256g--a1004","status_code":101,"method":"GET","resource":"/ws/boot.container?hostname=taishan200-2280-2s48p-256g--a1004-1&left_mem=250&tbox_type=dc&is_remote=false","testbox":"local-taishan200-2280-2s48p-256g--a1004-1"}
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:56.178+0800","from":"172.17.0.1:48526","message":"socket on closed","status_code":101,"method":"GET","resource":"/ws/boot.container?hostname=taishan200-2280-2s48p-256g--a1004-1&left_mem=250&tbox_type=dc&is_remote=false","testbox":"local-taishan200-2280-2s48p-256g--a1004-1"}
" send_mq_msg1"
" job_stage:  boot"
" send_mq_msg2"
" deadline: , state: requesting"
" send_mq_msg3 {\"job_id\" => \"\", \"testbox\" => \"local-taishan200-2280-2s64p-128g--a108-1\", \"deadline\" => \"\", \"time\" => \"2025-01-03T21:02:57+0800\", \"job_stage\" => \"boot\"}"
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:57.169+0800","message":"get job boot content","status_code":101,"method":"GET","resource":"/ws/boot.ipxe?mac=0a-ba-80-43-4f-88&hostname=taishan200-2280-2s64p-128g--a108-1&left_mem=115&tbox_type=vm&is_remote=false","testbox":"local-taishan200-2280-2s64p-128g--a108-1"}
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:57.169+0800","message":"qemu get job from ready queues by host_machine: local-taishan200-2280-2s64p-128g--a108","status_code":101,"method":"GET","resource":"/ws/boot.ipxe?mac=0a-ba-80-43-4f-88&hostname=taishan200-2280-2s64p-128g--a108-1&left_mem=115&tbox_type=vm&is_remote=false","testbox":"local-taishan200-2280-2s64p-128g--a108-1"}
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:57.174+0800","message":"move submit_custom to in_process result, /queues/sched/submit/vm-custom/10250103201457065, /queues/sched/in_process/local-taishan200-2280-2s64p-128g--a108/10250103201457065, true"}
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:57.174+0800","message":"get job from ready queues, etcd_job: {\"os_arch\" => \"aarch64\", \"my_account\" => \"zzk\", \"id\" => \"10250103201457065\", \"memory_minimum\" => \"8\", \"priority\" => \"11\", \"weight\" => \"100\", \"mvt\" => \"2025-01-03T21:02:57+0800\"}, host_machine: local-taishan200-2280-2s64p-128g--a108","status_code":101,"method":"GET","resource":"/ws/boot.ipxe?mac=0a-ba-80-43-4f-88&hostname=taishan200-2280-2s64p-128g--a108-1&left_mem=115&tbox_type=vm&is_remote=false","testbox":"local-taishan200-2280-2s64p-128g--a108-1"}
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:57.179+0800","message":"local-taishan200-2280-2s64p-128g--a108-1 got the job 10250103201457065","status_code":101,"method":"GET","resource":"/ws/boot.ipxe?mac=0a-ba-80-43-4f-88&hostname=taishan200-2280-2s64p-128g--a108-1&left_mem=115&tbox_type=vm&is_remote=false","testbox":"local-taishan200-2280-2s64p-128g--a108-1"}
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:57.179+0800","job_id":"10250103201457065","result_root":"/srv/result/host-info/2025-01-03/vm-2p8g/openeuler-22.03-lts-sp4-aarch64/10250103201457065","job_state":"set result root","status_code":101,"method":"GET","resource":"/ws/boot.ipxe?mac=0a-ba-80-43-4f-88&hostname=taishan200-2280-2s64p-128g--a108-1&left_mem=115&tbox_type=vm&is_remote=false","testbox":"local-taishan200-2280-2s64p-128g--a108-1"}
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:57.919+0800","message":"set job content, account: zzk"}
{"level_num":2,"level":"INFO","time":"2025-01-03T21:02:57.919+0800","message":"set sched/id2upload_dirs 10250103201457065, /result/host-info/2025-01-03/vm-2p8g/openeuler-22.03-lts-sp4-aarch64/10250103201457065","status_code":101,"method":"GET","resource":"/ws/boot.ipxe?mac=0a-ba-80-43-4f-88&hostname=taishan200-2280-2s64p-128g--a108-1&left_mem=115&tbox_type=vm&is_remote=false","testbox":"local-taishan200-2280-2s64p-128g--a108-1","job_id":"10250103201457065"}
"#!ipxe\n" +
"\n" +
"initrd http://172.168.131.113:8800/initrd/osimage/openeuler/aarch64/22.03-LTS-SP4/20240709.0.cgz\n" +
"initrd http://172.168.131.113:8800/kernel/aarch64/openeuler_defconfig_arm64/v5.10/modules.cgz\n" +
"initrd http://172.168.131.113:8800/initrd/deps/initramfs/debian/aarch64/sid/run-ipconfig/run-ipconfig_20201103.cgz\n" +
"initrd http://172.168.131.113:3000/job_initrd_tmpfs/10250103201457065/job.cgz\n" +
"initrd http://172.168.131.113:8800/upload-files/lkp-tests/aarch64/v2023.03.03.cgz\n" +
"initrd http://172.168.131.113:8800/upload-files/lkp-tests/09/09e898579ac0f03c59d0310132daa853.cgz\n" +
"initrd http://172.168.131.113:8800/initrd/build-pkg/container/openeuler/aarch64/22.03-lts-sp4/linux-next/v5.10.cgz\n" +
"kernel http://172.168.131.113:8800/kernel/aarch64/openeuler_defconfig_arm64/v5.10/vmlinuz user=lkp job=/lkp/scheduled/job.yaml ip=dhcp rootovl ro rdinit=/sbin/init prompt_ramdisk=0  initrd=20240709.0.cgz  initrd=modules.cgz  initrd=run-ipconfig_20201103.cgz  initrd=job.cgz  initrd=v2023.03.03.cgz  initrd=09e898579ac0f03c59d0310132daa853.cgz  initrd=v5.10.cgz rootfs_disk=/dev/vda\n" +
"echo ipxe will boot job id=10250103201457065, ip=${ip}, mac=${mac}\n" +
"echo result_root=/result/host-info/2025-01-03/vm-2p8g/openeuler-22.03-lts-sp4-aarch64/10250103201457065\n" +
......
```








