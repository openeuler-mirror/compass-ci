# compass ci job submit=>consume调度方案

本文所讨论jobs，均为stage=submit状态的job。

## 多队列需求

- anti-starvation
- priority/weight
- fast response
    - single scheduler: 0 delay
    - multi scheduler: 1s delay
- low overheads
    - caching
    - per-second ES COUNT(), discovering new jobs
    - find(ES) update cache on demand, if any aspect has new jobs

## 资源匹配需求

- tag matching (e.g. arch, `target_machines`, `tbox_type_arch`)
- resource matching (e.g. memory size)
- policy priority, select testbox
    - 优先分布到不同机器上，让负载均衡，跑得快
    - ccache 亲和

## ES<>cache<>多队列调度 问题挑战与方案

1. ES数据库保有全量stage=submit jobs，数量可能数以万计，且时不时会有新jobs加入
2. 在ES DB jobs数量巨大的情况下，scheduler无法缓存所有jobs信息
3. 在有多个调度器的情况下，调度器无法及时/准确感知所有jobs的存在

```
                 (scheduler2/3/...)
                      |    ^
                      v    |
              ES DB stage=submit jobs
                      ^    |
                      |    v
client submit job => scheduler => testbox (loop) consume job
```

因而scheduler进程在本地内存cache DB jobs的一个子集。
缓存维护算法需满足以下条件:
- 如果ES DB stage=submit jobs在某个`my_account=xxx`或`testbox=yyy`维度非空，则本地cache在该维度也必须非空

以上条件，配合`my_account`维度的多队列，是为了应对如下挑战

   user1: submit 10000 jobs, then
   user2: submit 1 job
   challenge: user2 shall not wait for all jobs from user1

## k=v tag型 资源匹配

all possible tag types on client submit:

    arch = aarch64|x86_64|...
    testbox = hw|vm|dc
              dc-8g|vm-2p8g|taishan200-2280-2s64p-256g
              taishan200-2280-2s48p-256g--a61

    # 提交时可选job字段，调度器亦可对其赋值
    target_machines = [taishan200-2280-2s48p-256g--a66, taishan200-2280-2s48p-256g--a88]

    # more device matches for 南向硬件兼容性测试
    sched.devices = []

    # more cache affinity selectors
    cache_dirs = [ccache/gcc, git/linux, ...]

The `testboxes`, `sched.devices`, `cache_dirs` etc. fields will be converted
to the below schedule input, so we only need care about them in the schedule
data structure and algorithms:

    # will be updated at submit time, save to ES DB for query below by phy_tbox
    target_machines =
            original target_machines
            &
            on testbox=taishan200-2280-2s64p-256g--a61: $testbox
            on testbox=taishan200-2280-2s64p-256g: $testbox # it's actually tbox group, useful for performance tests, not for compatibility tests due to different cards attached
            on testbox=hw: 'ANY'
            on testbox=vm|dc: 'ANY'
            on testbox=vm-8g: 'ANY'
            &
            on cache_dirs=[...]: select machines matching most cache_dirs, or 'ANY'
            &
            on sched.devices=[...]: select machines matching all devices, or fail submit

    # internal job field, won't be save to ES DB
    tbox_type_arch = hw-aarch64|vm-aarch64|dc-aarch64|...

## per-user/project multi-queue

To prevent light user being starved by heavy user, multi-queue is must-have.

job.queue is auto set to user account (1), and can be explicitly set by user to
well known projects (2) or named priority queues (3).

(1) and (2) can assign weight, for time sharing:

    50 admin
    30 single-build
    20 bisect
    10 user1
    10 user2

(3) can assign priority, higher priority is always consumed first

     9 vip (be careful - can starve lower priorities!)
     3 (default)
     1 idle (better submit on demand, in small batches)

## cache and accounting

    nr_db_jobs_by_user[job.my_account]
    nr_db_jobs_by_host[job.target_machines.each]

        Known nr_db_jobs stage=submit
        - updated once on startup, with ES COUNT() query
        - updated every 1 second, with ES COUNT() query, if has multi-scheduler
        - updated on each job submit/consume

    jobs_cache[job.id] = {partial job}

        Partial jobs cached in scheduler memory.

    jobid_by_user[job.my_account] = Set[jobids in order]

        User queues, reverse index for jobs_cache[]

    jobid_queue[vip|single-build|bisect|idle]

        Special queues
        job.queue=single-build

    jobid_by_host[phy_tbox] = Set[jobids in order]

        Reverse index for jobs_cache[], group by physical machine
        phy_tbox= job.target_machines.each

    host_freemem[phy_tbox] = size

        size=
        - 0/1 for hw tbox
        - freemem size for vm/dc host (provide by mult-qemu/docker)
        for quick dispatch on new job submit

## flow

- fact: job submit comes in batches, while job consume happens regularly, from day to night.
- submit jobs存入ES数据库 && update scheduler内部缓存
- consume job时从scheduler内部缓存搜索
- 定期/按需从ES数据库搜索stage=submit jobs, 同步到调度器内部缓存

### on startup
### on every 1 second

    do ES COUNT(group-by job.my_account field) query
        # 查jobs表，按my_account分组统计数量。这一聚合统计可覆盖全集，且速度快
        # https://www.elastic.co/cn/blog/new-in-elasticsearch-7-13-even-faster-aggregations

        if nr db jobs can all be cached (e.g. < 10000):
            do a single stage=submit query to sync data to jobs_cache[]
        else:
            # caution: ES聚合统计数字可能不完全精确
            compare with nr_db_jobs_by_user[]

            for each nr_db_jobs_by_user[] mismatch
                query ES to pull new jobs into jobs_cache[]

            for each jobid_by_user[my_account] going empty, but nr_db_jobs_by_user[] non-zero
                query ES to pull new jobs into jobs_cache[]
                select my_account=user stage=submit FROM jobs limit=1000

    do ES COUNT(group-by job.target_machines field) query
        # ditto

    trigger consume job

### on new job submit

    update all data structure
    trigger consume job

### on job done

    update all data structure
    trigger consume job

### on tbox consume job

    multi-qemu/docker provides

        arch = aarch64
        tbox_types = [dc, vm] | [dc]
        host_machine = taishan200-2280-2s48p-256g--a66
        free_memory = 20G
        cache_dirs (ls -d */*/ on local $cache_root)

    hw tbox provides

        ip, mac, optional hostname
        # scheduler then query $LKP_SRC/hosts/$hostname for more info
        # scheduler can maintain a hosts_cache[], keep updating host_freemem[]

    trigger consume job

### consume job core logic

    sort host_freemem[], large first # 负载均衡policy priority

    for job in jobid_queue[vip]
               jobid_by_user[my_account] in dynamic order on weight
               jobid_queue[idle]

        for host in host_freemem:

            filter tbox_type_arch
            filter job.target_machines
            filter job.need_memory
            return (job, host) if found

## use scenarios

### how a user can avoid later urgent job be starved by his earlier batch jobs

    user1 submit 1000 jobs for proj1
    user1 submit 1 jobs for proj2, queue=vip|single-build
