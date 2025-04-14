job依赖和事件等待，要支持两大类场景:
1) job对job的依赖: workflow scheduler: DAG parse+schedule
2) job对cgz的依赖: job scheduler: auto build job submit+wait (e.g. job needs linux kernel commit's binary => create+submit pkgbuild job => wait)
3) 一个脚本或服务对一组jobs的依赖等待: wait-jobs HTTP/WS API

本篇讲 wait-jobs 实现

# 应用场景

1) bisect的每一步，等待提交的多个jobs全部结束(性能测试)/逐个结束(功能测试)，以便判断good/bad
2) 用户submit时加-m，或事后请求监控一组job ids, 实时接收进度信息，等待结束
3) 多机测试中，各client等待所有各方ready，获得各方role/ip信息，然后同时开跑

其中(1)需要等待job结束的能力
其中(2)(3)需要更细粒度的，监控或等待job中某个key变成某个value的能力

# 基本假设

job => scheduler => watch-jobs module => HTTP client
- full job 先submit到scheduler，然后存入ES
- 永远可以从ES查到所有job及其当前状态

# API and HTTP client

该API采用类似NFS server/client的设计：NFS dump server可随时重启。
类似的，API的服务端可随时崩溃重启，客户端只需重新连接API，参数重新提交，继续等待API参数中的jobs条件即可。
客户端可把如下loop包装为一个本地lib function，方便调用。

	loop
		curl http://ip/watch-jobs --json '
		{
		    expect_jobs: {
			job_id1: { job_stage: complete } # 等待job_id1的job_stage字段变成complete
			job_id2: { job_stage: package-uploaded } # 等待job_id2的job_stage字段变成package-uploaded, 对rpmbuild有意义，这样其他脚本可以立即开始使用输出的rpm包，而不必等待rpmbuild job接下来可能要跑的unit test
			job_id3: { job_stage: started } # 等待job_id3的job_stage字段变成started，用于多机测试中client对service的等待 (service状态：running => start daemon => started)
			job_id4: { job_stage: wait_peer } # 等待job_id4的job_stage字段变成wait_peer，用于多机测试中client对所有其它client的等待 (10 clients wait all ready => 同步开启压测)
			...
		    }
		    # future: add options here
		    # option1: value1
		}'

		# curl will block until
		# - timeout or service restart: just retry
		# - any job 满足条件: remove that job => run local logic => retry
        #   因为在多机测试中: submit 10 jobs, wait for first error

TODO: add 'complete' job lifecycle stage, meaning extract-stats done, all job data are complete, job成为完全体

finish stage: means "run finish"
complete stage: extract-stats => ES  => data ready => complete
data ready: the below fields are put in ES
- job.stats.xxx
- job.errid
- job.job_health

# on API call

input: API options
action:
- query ES for missing jobs_cache[] for all request.expect_jobs.$job_id
- add job ids to jobid2clients[] to receive event updates
- spawn a channel: on initial/every-10s, search jobs in cache/ES => send fake/initial event for the jobs

# 数据结构(in memory)

    # API request json
    watch_clients[$client_id] = {expect_jobs[], client ip, request time, ...}

    jobid2clients[$job_id] = [$client_id, ...]

# on job update

input:
- jobid
- jobs_cache[jobid]

action:
for client in jobid2clients[jobid]:
	if delete: # 很重要，避免job异常时，client永久等待一个永远无法满足的job k=v状态
		notify_client
	if match watch condition:
		notifywakeup_client

notifywakeup_client:
    update expect_jobs[], remove the matched fields
    send JSON with the remaining expect_jobs[] 
    close client if expect_jobs[] goes empty

# related services
- watch-jobs (merge service)
- monitoring (reuse code, merge in future)
- src/scheduler/request_cluster_state.cr (reuse code, replace in future)

- src/scheduler/auto_depend_submit_job.cr (job缺cgz依赖 => 自动submit+wait makepkg job)
- src/scheduler/plugins/pkgbuild.cr (job ss字段依赖缺失 => 自动submit+wait makepkg job)

- pipeline (reuse code)
- sbin/auto_submit (to submit workflow to pipeline service)

# related doc
- /c/cci/todo/data/data-post-processing-flow.md
- /c/cci/todo/build/auto-build-design.md
- /c/cci/todo/scheduler/auto-depend.md
- schedduler find_job_boot()
