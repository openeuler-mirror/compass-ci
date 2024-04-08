[toc]

# compass-ci debug tips

## 任务提交场景

### job提交后未执行

**当出现job提交后，长时间未执行会无响应时，可以从job执行流程来进行分析：**

- 用户触发submit提交任务-> 写ready队列，写id2job队列 (scheduler调度器服务)

- 执行机拉取任务(multi-docker, multi-qemu, ipxe) -> move ready队列  to in_process队列，返回job (scheduler调度器服务)

- 执行机完成任务，上传结果  (docker，qemu，native) ->  move in_process队列  to extract-stats队列  (scheduler调度器服务)
- 解析结果，删除id2job, extract-stats，写job到post-extracts (extract-stats服务)
- 任务处理，删除post-extracts (post-extract服务)



**定位job问题**

```shell
# 1 查看job状态
# es_find _id=$job_id | grep job_

duanpengjie@z9 ~% es-find _id=z9.27483948 | grep job_
          "job_origin": "jobs/borrow-1h.yaml",
          "job_state": "boot",
          "job_stage": "boot",
            "http://172.168.131.2:3000/job_initrd_tmpfs/z9.2748394

# 2 查看调度器中的job日志
# docker logs -f sub-fluentd | grep scheduler-3000 | grep $job_id 
docker logs -f sub-fluentd | grep scheduler-3000 | grep z9.27483948 

# 10分钟内的日志， 适用于刚刚提交的job查看
docker logs -f sub-fluentd --since 10m| grep scheduler-3000|grep z9.27483948
```





### result结果未生成

通过es-find _id=$job_id 能够获取到es数据库中该job的信息

```bash
# 获取result路径
# es-find _id=$job_id  | grep result

duanpengjie@z9 ~% es-find _id=z9.27484002 | grep result
Ignoring unf_ext-0.0.8.2 because its extensions are not built. Try: gem pristine unf_ext --version 0.0.8.2
          "result_root": "/result/borrow/2024-04-08/dc-32g/openeuler-22.03-LTS-SP3-aarch64/86400/z9.27484002",
          "upload_dirs": "/result/borrow/2024-04-08/dc-32g/openeuler-22.03-LTS-SP3-aarch64/86400/z9.27484002",
          "result_service": "raw_upload",

# 跳转到result 
cd /srv/result/borrow/2024-04-08/dc-32g/openeuler-22.03-LTS-SP3-aarch64/86400/z9.27484002
```

当目录下没有job的result信息，表示extract-stats服务解析错误

或者调度器实现 move in_process队列  to extract-stats队列  时发生了错误







## 系统状态查询

### 查看任务队列

当前任务在etcd和es中

```bash
# 查看etcd信息可以通过etcdctl指令

# 查看待运行任务
duanpengjie@z9 ~% etcdctl get --prefix /queues/sched/ready | head -n10
/queues/sched/ready/2288hv3-2s24p-384g--b31/zhengqiaoling2@huawei.com/z9.27482649
{"id":"z9.27482649"}
/queues/sched/ready/2288hv5-2s28p-256g--b1003/wufengguang@huawei.com/z9.27482548
{"id":"z9.27482548"}
/queues/sched/ready/2288hv5-2s28p-256g--b1003/wufengguang@huawei.com/z9.27482562
{"id":"z9.27482562"}
/queues/sched/ready/2288hv5-2s28p-256g--b1003/wufengguang@huawei.com/z9.27482785
{"id":"z9.27482785"}
/queues/sched/ready/2288hv5-2s28p-256g--b1003/wufengguang@huawei.com/z9.27482899
{"id":"z9.27482899"}

# 查看执行中的任务
duanpengjie@z9 ~% etcdctl get --prefix /queues/sched/in_process | head -n10
/queues/sched/in_process/2288hv3-2s12p-768g--b16/liushuai136@h-partners.com/z9.27127603
{"id":"z9.27127603"}
/queues/sched/in_process/2288hv3-2s12p-768g--b16/liushuai136@h-partners.com/z9.27461760
{"id":"z9.27461760"}
/queues/sched/in_process/2288hv3-2s16p-256g--b11/liushuai136@h-partners.com/z9.27444304
{"id":"z9.27444304"}
/queues/sched/in_process/2288hv3-2s20p-256g--b25/weijihuiall@163.com/z9.24826453
{"id":"z9.24826453"}
/queues/sched/in_process/2288hv3-2s24p-288g--b20/wangchongyang23@huawei-partners.com/z9.25558947
{"id":"z9.25558947"}
```



1. ready队列中的任务没有被移到in_process中，可能是由于以下情况
   - testbox没有设置正确
   - 没有符合规格的执行机
   - 调度器在访问etcd时出现异常
2. in_process队列中的任务没有被移动，可能是由于以下情况
   - 调度器在访问etcd时出现异常
   - lifecycle服务出现异常



### 查看历史日志

当前所有服务的日志会被fluentd收集

```bash
# docker logs -f sub-fluentd | grep $服务名称

duanpengjie@z9 ~% docker logs -f sub-fluentd | grep extract-stats
2024-04-08 14:05:12.000000000 +0800 extract-stats: Etcd::Model::WatchEvent(@type=PUT, @kv=Etcd::Model::Kv(@key="/queues/extract_stats/z9.27483776", @value="{\"id\" => \"z9.27483776\"}", @create_revision=280016132, @mod_revision=280016132, @version=1, @lease=nil))
2024-04-08 14:05:22.000000000 +0800 extract-stats: {"level_num":2,"level":"INFO","time":"2024-04-08T14:05:22.713+0800","job_id":"z9.27483776","job_state":"extract_result_finished"}
2024-04-08 14:05:22.000000000 +0800 extract-stats: {"level_num":2,"level":"INFO","time":"2024-04-08T14:05:22.856+0800","job_id":"z9.27483776","job_state":"extract_stats_finished"}
2024-04-08 14:05:22.000000000 +0800 extract-stats: {"level_num":2,"level":"INFO","time":"2024-04-08T14:05:22.860+0800","message":"extract-stats delete id2job from etcd z9.27483776: Etcd::Model::DeleteResponse(@header=Etcd::Model::Header(@cluster_id=14841639068965178418, @member_id=10276657743932975437, @revision=280016151, @raft_term=56), @deleted=1, @prev_kvs=[])"}

```



### 查看es数据库

