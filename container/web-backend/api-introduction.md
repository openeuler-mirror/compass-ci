# API 介绍
web-backend 主要为一些定制化API，主要支持如下方面的功能：
- 测试结果查询，分析比较等可视化功能
- 测试资源查询与监控
- 分析服务及测试日志，冒泡job以及服务出现的错误

本文着重介绍较为复杂API，辅助理解代码
简单API通过查看注释和代码很容易理解，本文只做简单描述

## get '/web_backend/compare_candidates'
用于给 https://compass-ci.openeuler.org/compare(下文将用`WEB`代替 `https://compass-ci.openeuler.org`) 页面 提供compare参数的选项

## get '/web_backend/compare'

### 先要理解简单的比较
如比较两组job， compare job1,job2  job3,job4

可执行命令工具来比较： `compass-ci/sbin/compare id=job_1,job_2 id=job3,job4`
```
     base : job1, job2  --> query job_1,job_2 from ES/jobs --> [job_1, job_2] --> [job_1['stats'], job_2['stats']] --> matrix_1
challenger: job3, job4  --> query job_1,job_2 from ES/jobs --> [job_3, job_4] --> [job_3['stats'], job_4['stats']] --> matrix_2
		|
		v
	compare matrix_1 matrix_2
		|
		v
	    result
	    eg: compass-ci/sbin/compare id=crystal.5238093,crystal.5179333 id=crystal.5150356


crystal.5238093                crystal.5150356
crystal.5179333
	
                   0                               1  metric
--------------------  ------------------------------  ------------------------------
          %stddev       change            %stddev
             \             |                 \
      300.18             +0.0%        300.18          iperf.time.elapsed_time
      300.18             +0.0%        300.18          iperf.time.elapsed_time.max
        0.00               0            1.00          iperf.time.involuntary_context_switches
     3648.00             +0.0%       3648.00          iperf.time.maximum_resident_set_size
      247.00             +0.0%        247.00          iperf.time.minor_page_faults
540196036.83 ± 84%      -98.3%    9279128.11          boot-time.idle 
^		^           ^
avg		标准偏差   变化率
	        ^
                这一组样本数是两个，因此有偏差


```

**重要概念解释**
- job['stats']
```
eg: job['stats']
{
	"iperf.tcp.sender.bps": 28641150000.0,
	"iperf.tcp.receiver.bps": 28640810000.0,
        "softirqs.CPU35.SCHED": 14358457,
        "softirqs.CPU58.NET_TX": 7826,
        "softirqs.CPU69.NET_TX": 28823,
	...
}
```

- matrix
```
eg: matrix(merge 2 job['stats'])
{
	"iperf.tcp.sender.bps" => [28641150000.0, 28110150000.0],
	"iperf.tcp.receiver.bps" => [28640810000.0, [28340810000.00],
        "softirqs.CPU35.SCHED": [14358457, 14080010 ],
        "softirqs.CPU58.NET_TX": [7826, 7526],
	...			  ^      ^
}				  ^      ^
				  ^      ^
job1['stats']['softirqs.CPU58.NET_TX']   job2['stats']['softirqs.CPU58.NET_TX']
```
  

### API: /web_backend/compare 比较逻辑

接受 WEB/compare 传入的参数，运行 ，返回性能测试的比较结果。
输入：
  - query_conditions
    eg: os=openeuler suite=iperf
  - dimension
    eg: os_version

逻辑如下：
```
  
 	query job_list from ES/jobs by $query_conditions
		|
		v
        auto group job_list with different params: tbox_group, os, os_arch, os_version, pp.*.* (ignore dimension(os_version))
		|
		|    eg:
		|	{
		|	  "tbox_group=2p8g os=openeuler os_arch=x86_64  pp.iperf.runtime=60 => $1st_job_list_1 : Array(Job),
		|	  "tbox_group=2p8g os=openeuler os_arch=aarch64 pp.iperf.runtime=60 => $1st_job_list_2 : Array(Job),
		|	  ...
		|
		|	}
		|
		v
	group each 1st_job_list by dimension(os_version)
		|
		|	eg
		|	{
		|	  "tbox_group=2p8g os=openeuler os_arch=x86_64  pp.iperf.runtime=60 => {
		|              "20.03" => $2nd_job_list_1 : Array(Job),
		|              "21.03" => $2nd_job_list_2 : Array(Job)
		|	  },
		|	  "tbox_group=2p8g os=openeuler os_arch=aarch64 pp.iperf.runtime=60 => {...},
		|	  ...
		|	}
		|
		v
	extract each job['stats'] of $2nd_job_list
		|
		|	eg:
		|	{
		|	  "tbox_group=2p8g os=openeuler os_arch=x86_64  pp.iperf.runtime=60 => {
		|              "20.03" => matrix_1,
		|	       "21.03" => matrix_2
		|	  }
		|	  ...
		|	}
		v	
	foreach each 1st_group, compare all dimensions matirx
		|	{
		|	  "tbox_group=2p8g os=openeuler os_arch=x86_64  pp.iperf.runtime=60 => {
		|		compare matrix_1, matrix_2
		|	  }
		|	}
		v
	part result like bellow:

os=openeuler os_arch=aarch64 pp.iperf.protocol=tcp pp.iperf.runtime=30 tbox_group=vm-2p16g


               20.03                           20.09                       20.03-SP1                            test  metric
--------------------  ------------------------------  ------------------------------  ------------------------------  ------------------------------
          %stddev       change            %stddev       change            %stddev       change            %stddev
             \             |                 \             |                 \             |                 \
3.372684e+10 ± 26%      +31.1%  4.421639e+10           -100.0%          0.00           -100.0%          0.00          iperf.tcp.receiver.bps
3.377156e+10 ± 26%      +31.0%  4.425679e+10           -100.0%          0.00           -100.0%          0.00          iperf.tcp.sender.bps
       30.22 < 1%        +1.2%         30.59            -99.8%          0.07           -100.0%          0.00          iperf.time.elapsed_time
       30.22 < 1%        +1.2%         30.59            -99.8%          0.07           -100.0%          0.00          iperf.time.elapsed_time.max
        1.00           -100.0%          0.00          +1.3e+4%        127.00           -100.0%          0.00          iperf.time.exit_status
```

## /web_backend/get_jobs

使用了ES的查询能力，支持`WEB/jobs` 页面搜索，查看job, 每个job返回指定字段（具体有哪些字段见代码中的注释）
能力对标命令行工具：compass-ci/sbin/es-find k1=v1 k2=v2

## /web_backend/active_testbox

使用ES 查询 + 聚合能力，对ES/testbox 按照`dc`, `vm`, `physical` 维度聚合， 以获得正在请求任务的testbox

## /web_backend/srpm_info

## /web_backend/compat_software_info

## /web_backend/query_compat_software

## /web_backend/get_repos

## /web_backend/performance_result
支持性能看板, 基于compass-ci/lib/compare.rb 开发

### x轴为测试参数，如pp.fio-basic-setup.bs, pp.fio-basic-setup.test_size

- input/body:
  ```
  {
    "filter":{"suite":["fio-basic"],"pp.fio-setup-basic.rw":["randrw"],"group_id":[]},		# filter, 用于ES/jobs 搜索条件
    "metrics":["fio.read_iops","fio.read_bw_MBps","fio.write_iops","fio.write_bw_MBps"], 	# 筛选出指定的job['stats'][$metric]
    "series":[{"os":"openeuler","os_version":"20.03-LTS-SP1-iso"},				# 指定比较系列
              {"os":"openeuler","os_version":"21.03-iso"}],
    "x_params":["bs"],										# x轴参数
    "test_params":["pp.fio-setup-basic.rw"]							# 分组数量较少，则不会自动合并重复参数，
    												  指定分组参数，可以简化分组参数，移除不必要的参数
  }

  ```

- internal flow:
  ```
    get job_list by input['filter'] from ES/jobs
    	|
	v
    1st AUTO_GROUP job_list BY tbox_group, os, os_arch, os_version, pp.*.* (ignore series, pp.xx.input[$x_parms])
    	| {
	|   "os_arch=aarch64 pp.fio.nr_threads=1 pp.fio.runtime=60, ..." => job2_list,
	|   "os_arch=aarch64 pp.fio.nr_threads=128 pp.fio.runtime=60, ..." => job2_list
	| }
	v
    2nd AUTO_GROUP 1st-group BY pp.xx.input[$x_parms]
    	| {
	|   "os_arch=aarch64 pp.fio.nr_threads=1 pp.fio.runtime=60, ..." => {
	|     "4k" => job1_1_list,
	|     "16k" => job1_1_list,
	|     ...
	|   }
	|   "os_arch=aarch64 pp.fio.nr_threads=128 pp.fio.runtime=60, ..." => {...}
	| }
	|    
	v
    3rd GROUP 2nd-group  BY output['series']
	| {
        |   "os_arch=aarch64 pp.fio.nr_threads=1 pp.fio.runtime=60, ..." => {
        |     "4k" => {
	|	"openeuler 20.03-LTS-SP1-iso" => job_list  ----> matrix  \
	|								  + ----> compare 2 matrices --> compare_values
	|	"openeuler 21.03-iso" => job_list ----> matrix		 /
	|     },
        |     "16k" => {...}
        |     ...
        |   }
        |   "os_arch=aarch64 pp.fio.nr_threads=128 pp.fio.runtime=60, ..." => {...}
        | }
	| 		
	|
	|
	v
    compare each group(group1.group2.$serise_2 vs group1.group2.$serise_1)
    	|  {
        |    "os_arch=aarch64 pp.fio.nr_threads=1 pp.fio.runtime=60, ..." => {
        |      "4k" => {
	|        fio-read_iops => {"avg": 177287, "change": 0, "deviation": 4.6104 }
	|	 fio.read_bw_MBps => {...},
	|	 ...
	|       }
	|     }
	|  }
        | 	
	|	
	v
    foamat compare result for echart, compare_result结构重组
        抽取 group1.group2.series.$metric ---> title
    	抽取 2nd group_kes (4k, 16k, ...) ---> datas.$key.x_params
	|
	v
     output
```

- response:

  [
    {
      "title":"fio-read_iops",				# fio-read_iops
      "test_params":"pp.disk.nr_ssd=1",
      "testbox":"taishan200-2280-2s48p-256g--a1009",
      "datas":{
        "change":[
          {
	    "series":"openeuler 21.03-iso vs openeuler 20.03-LTS-SP1-iso",
	    "data":[0,0,0,0,0,0,0,0],
	    "x_params":["4k","16k","32k","64k","128k","256k","512k","1024k"]
	  }
	],
        "average":[
        {
          "series":"openeuler 20.03-LTS-SP1-iso",
          "data":[177287.5573,105380.9246,46947.1869,22115.4787,10917.9205,5669.5999,3107.2884,1622.6533],
          "deviation":[4.6104,1.6582,2.4908,1.5477,0.9364,0.6677,0.7019,1.198],
          "x_params":["4k","16k","32k","64k","128k","256k","512k","1024k"]
        },
        {
          "series":"openeuler 21.03-iso",
          "data":[0,0,0,0,0,0,0,0],
          "deviation":[0,0,0,0,0,0,0,0],
          "x_params":["4k","16k","32k","64k","128k","256k","512k","1024k"]}]}},
     {
       "title":"fio-read_bw_MBps","test_params":
       "pp.disk.nr_ssd=1",
       "testbox":"taishan200-2280-2s48p-256g--a1009",
       "datas":{...}
     }
  ]

```
 
### x轴为测试子项(job['stats'][$metric])
```
      input_data: {
          filter: {
            suite: ["unixbench"],
            "pp.unixbench.nr_task": [1, 96],
            "pp.unixbench.mount_to": ["/test"],
            group_id: [],
          },
          metrics: [
            "unixbench.Dhrystone_2_using_register_variables",
            "unixbench.Double-Precision_Whetstone",
            "unixbench.Execl_Throughput",
            "unixbench.File_Copy_1024_bufsize_2000_maxblocks",
            "unixbench.File_Copy_256_bufsize_500_maxblocks",
            "unixbench.File_Copy_4096_bufsize_8000_maxblocks",
            "unixbench.Pipe_Throughput",
            "unixbench.Pipe-based_Context_Switching",
            "unixbench.Process_Creation",
            "unixbench.Shell_Scripts_(1_concurrent)",
            "unixbench.Shell_Scripts_(8_concurrent)",
            "unixbench.System_Call_Overhead",
            "unixbench.System_Benchmarks_Index_Score",
          ],
          series: [
            { os: "openeuler", os_version: "20.03-LTS-SP3-iso" },
            { os: "openeuler", os_version: "22.03-LTS-iso" },
          ],
          x_params: ["metric"],					# x_params 为metric, 则以metric作为轴
        },
      }
```

- internal flow
   2nd AUTO_GROUP 1st-group BY job['suite']
   其他逻辑同上

- output

```
[
  {
    "title":"unixbench",
    "test_params":"pp.unixbench.nr_task=96","testbox":"taishan200-2280-2s48p-256g--a1008",
    "datas":{
       "change":[
         {
	   "series":"openeuler 20.03 vs openeuler 20.03-LTS-SP3-iso",
	   "data":[0,0,0,0,0,0,0,0,0,0,0,0,0],
	   "x_params":[
	     "unixbench-Dhrystone_2_using_register_variables",
	     "unixbench-Double-Precision_Whetstone",
	     "unixbench-Execl_Throughput",
	     "unixbench-File_Copy_1024_bufsize_2000_maxblocks",
	     "unixbench-File_Copy_256_bufsize_500_maxblocks",
	     "unixbench-File_Copy_4096_bufsize_8000_maxblocks",
	     "unixbench-Pipe_Throughput",
	     "unixbench-Pipe-based_Context_Switching",
	     "unixbench-Process_Creation",
	     "unixbench-Shell_Scripts_(1_concurrent)",
	     "unixbench-Shell_Scripts_(8_concurrent)",
	     "unixbench-System_Call_Overhead",
	     "unixbench-System_Benchmarks_Index_Score"
	   ]
	 }
	],
	"average": [...]
    }
  },
  ...
]
```

### update 版本看板，自动选取series
```
- input
{
  "filter":{
  	"interval_type":["openeuler-update"],
	"os":["openeuler"],
	"suite":["stream"],
	"os_version":["20.03-LTS-SP2-iso"],
	"group_id":[]
  },
  "metrics":["stream.copy_bandwidth_MBps","stream.scale_bandwidth_MBps","stream.add_bandwidth_MBps","stream.triad_bandwidth_MBps"],
  "series":["group_id"],			# 指定series条件为group_id
  "x_params":["metric"],
  "max_series_num":2				# 1st auto-group , 2nd auto-group 将选取最新的2个group_id 作为series
}
```
- internal flow
 3rd GROUP 2nd-group  BY output['series'], 每一组数量是: output['max_series_num']
 其余逻辑同上

- output
```
[
  {
    "title":"stream",
    "test_params":"pp.stream.array_size=100000000 pp.stream.nr_threads=96 pp.stream.omp=false",
    "testbox":"taishan200-2280-2s48p-256g--a1008",
    "datas":{
      "change":[
        {
	  "series":"openeuler-20.03-LTS-SP2-update_20220118 vs openeuler-20.03-LTS-SP2-update_20220117",
	  "data":[-2.9,-1.9,-0.8,-2.2],
	  "x_params":["stream-copy_bandwidth_MBps","stream-scale_bandwidth_MBps","stream-add_bandwidth_MBps","stream-triad_bandwidth_MBps"]
	}
      ],
      "average":[
        {
	  "series":"openeuler-20.03-LTS-SP2-update_20220117",
	  "data":[12109.4,11574.5,9754.0,10179.8],
	  "deviation":[0.0,0.0,0.0,0.0],
	  "x_params":["stream-copy_bandwidth_MBps","stream-scale_bandwidth_MBps","stream-add_bandwidth_MBps","stream-triad_bandwidth_MBps"]
	},
	{
	  "series":"openeuler-20.03-LTS-SP2-update_20220118",
	  "data":[11752.2,11357.2,9673.7,9957.7],
	  "deviation":[0.0,0.0,0.0,0.0],
	  "x_params":["stream-copy_bandwidth_MBps","stream-scale_bandwidth_MBps","stream-add_bandwidth_MBps","stream-triad_bandwidth_MBps"]
	}
      ]
    }
  }
]
```

## /web_backend/query_field

使用ES聚合能能力，返回指点范围的jobs 的某个字段有那些值
```
 POST /web_backend/query_field
 - header: "Content-Type: Application/json"
 - body: json
   eg:
   {
     "filter": {"suite": ["stream"]},
     "field": "os"
   }
   return:
   eg: ["openeuler", "centos", "debian", "openanolis", "kylin", "uniontechos"]
```

能力对标 compass-ci/sbin/es-find $filter -c/--count filed1,field2,...

## /web_backend/get_testboxes

## /web_backend/get_tbox_state

## /web_backend/get_repo_statistics

## /web_backend/get_jobs_summary
根据输入的filter + dimension 统计ES/jobs 中的job['stats']['$metrc'] fail/success 数量，
并按照 dimension分组

## /web_backend/get_job_error
根据输入的filter，
获得jobs_summary job['stats']['$metrc'] 为fail（error_id）对应的error_essage


## /web_backend/git_mirror_health

## /web_backend/active_service_error_log
获取5天内service_log 有哪些，并按照出现频次排序
支撑mutt 中top service log

## /web_backend/active_stderr
获取5天内job['stats']['stderr.xxx'] 有哪些，并按照出现频次排序
支撑mutt 中top job error

## /web_backend/job_boot_time

## /web_backend/test_matrix

## /web_backend/host_info

根据输入的主机名/testbox 到服务器的/c/lab-$lab/hosts 查询host_info
可优化为从ES中查询host_info
