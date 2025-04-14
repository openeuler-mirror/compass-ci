# compass ci 问题挑战

- 内存消耗大
- etcd 不稳定，经常性connection reset
- etcd 太慢
- 从未从etcd多机一致性受益，是为伪需求
- 一般企业需要：小而美、简单稳定的CI平台

前几年影响稳定的主要因素：

    etcd full, reset
    disk full, broken
    计划内停电

很少是个问题：

    单机故障：只有过一次kernel oops
    scheduler logic error -- just fix and restart
    scheduler升级：无状态，可随时重启。重启期间，clients can just retry and recover

# compass ci 简化方案

remove etcd depends out of the core services
- replace queue with ES search + local match, with local memory cache
- remove etcd from job `submit<=>consume<=>stats<=>watch` step by step
- one single scheduler executable for serving submit/consume/watch clients

Main bottleneck will be CPU computation, like json/job conversion,
submit/consume/watch jobs matching/filtering/sorting. These main time consuming
tasks won't be bottleneck: es io; create job cgz, since they are IO or forked task.

- the single source for ES/manticore DB job create/update/serve

manticore will have 2 kind of cols:

    1. mysql cols: a, b
    2. json cols: jj

The search will reference them like

    select a, b, jj.xxx, jj.yyy

- cache recent jobs info in local memory
- offer websocket job watch/wait API
- scheduler单进程模式
- scheduler内部workers channel互通消息
- remove nginx dispatcher

    nginx => N schduler, backed by ES/etcd/redis
    => simplify to =>
    1 scheduler, backed by manticore/redis
    1 scheduler => watcher => 分发

- extract-stats, post-extract services合入scheduler
- post-extract service 插件化

add retry in clients
- submit retries
- consume job retries (by nature)
- close job retries (2 clients: testbox http get, lifecycle)
- watch retries (by nature)
- test progress, update stage: retry not necessary

# submit=>consume调度方案

## 基本方案

submit 时存入ES数据库, scheduler内部缓存
consume 时从scheduler内部缓存搜索，定期从ES数据库搜索同步

## k=v tag型 资源匹配

job提交方描述资源需求，例如

    arch=aarch64
    hw_type=hw hw_type=vm hw_type=dc
    tbox_group=taishan200-2280-2s48p-256g
    testbox=taishan200-2280-2s48p-256g--a66

maybe future:

    vm_host=taishan200-2280-2s48p-256g--a66
    dc_host=taishan200-2280-2s48p-256g--a66
    more device matches for 南向硬件兼容性测试

`job_stage=submit`的jobs缓存在scheduler内部，做内部查询
在内存中，对每个如上k，建立一个反向hash

consume方提供tag list，并一一在如上hash中搜索jobs, 然后做一个集合交集，取得初步job list1

all jobs 分桶to

    jobs1[arch=aarch64] = 1000 jobs
    jobs2[arch=x86] = 2000 jobs
    jobs3[hw_type=dc] = 2000 jobs

comes a testbox, with tags

	arch=aarch64
	hw_type=dc

scheduler will get 2 job list, then intersect

`hw_type-arch` can be merged into 1 single tag, to reduce the intersection.

## memory 大小型 资源匹配

job list1对memory需求做过滤，得到job list2，发给测试机

in job, has either field for requirement:

	memory_minimum
	memory
	hw.memory

comes a testbox, with

	memory-avail=20G

## priority, 多租户公平性

job list1基于租户(动态优先级)、优先级、提交时间排序，取得job list3 ordered list
scheduler可把它cache到，以减少匹配计算量

    job_list3_cache[tags]

## race condition

### prevent a job be consumed by 2+ testboxes

#### 完全避免该race condition:

way1: 用redis/etcd原子操作

    https://stackoverflow.com/questions/50309206/redis-atomic-get-and-conditional-set
    NX - Only set the key if it does not already exist.
    https://redis-doc-test.readthedocs.io/en/latest/commands/setnx/

way2: 调度器单一线程

    try_get(job) use global var
    atomic set not necessary, since that's for real threads

way3: 调度器pool内部通信协调

#### 减少race window

way4: 读取es数据库job3
如es数据库已被更新，则job3已被消费，转下一个job

2. 然后发给测试机

here es will become inconsistent, if scheduler crashes in this tiny window

3. 更新es数据库

4. job跑起来后，发API更新es数据库

在2/3之间，有极小的race condition, scheduler crash可导致es数据库未更新。
可以在test box set job_stage=running时再检查一下，以消除不一致
- if es job_stage=submit, update to new stage
- (只有way4才需要这里配合) if es job_stage=running/..., 那么有其他测试机在执行该job了，let current testbox abort

## 10w submit状态 jobs数据量

10w * 1kb = 100MB
