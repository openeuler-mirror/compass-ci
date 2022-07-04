# extract-stats service
  extract-stats 服务为每一个job提取结果，并标准化处理后存储到`ES/jobs/_doc/$job["stats"]`

## 1. 代码运行逻辑
### 1.1 extract-stats
   代码：compass-ci/src/extract-stats/extract_stats.cr:

   ```
		main
		|
		+---->	spawn{ watch ETCD queue: extract_stats }
		|			|
		|			v
		|	Channel   <---  send $queue/$job_id to Channel
		|	|
		v	|
		loop:	v
		  Channel.recive $queue/$job_id)
		  spawn {StatsWorker.new.handle($queue/$job_id)}
   ```

### 1.2 stats_worker handle
    代码：compass-ci/src/extract-stats/stats_worker.cr

    ```
       $queue/$job_id) --> job_id
				|
				v
			   get job from ES/jobs/_doc/$job_id
				|
				v
			   get $result_root/stats.json by call cmd: `compass-ci/sbin/result2stats job['result_root']`
				|
				v
			  save $result_root/stats.json  ----> ES/jobs/_doc/job['stats']
				|
				| buildpkg test
				+------>  save buildpkg.json(error_ids) --> ES/jobs/_doc/job['error_ids']
				|	  foreach buildpkg.json do |error_id|
				|  		save error_id--> ES/regression/_doc/$error_id
				|		start besect if error_id is new
				|
				v
			delete ETCD $queue/$job_id)
    ```

### 1.3 result2stats $result_root
   code: compass-ci/sbin/result2stats

   ```
	run: result2stats $result_root
		|
		v
		open $result_root
		|
		v
	progrom_list = $result_root/* & lkp-tests/stats/* + lkp-tests/$job['suite']
		|
		v
	progrom_list.each do |program| # $program same name with $log
		|	lkp-tests/stats/$program < $result_root/$log
		|		|
		|		v
		|	$result_root/$log.json
		|
		v
	merge and handle(sum, avg, event, ... each stats['metric']) $result_root/*.json
		|
		v
	$result_root/stats.json
   ```

更多介绍参考：
	compass-ci/doc/result/data-process.md

## 问题定位方位以及常见问题总结
### 调试手段
- 查看服务器日志，找到问题原因
  服务器： docker logs -f sub-fluentd |grep extract-stats

- 本地调试 `compass-ci/sbin/result2stats $result_root`
   1. 获取该job的result_root及其所有文件， 可通过如下方式：
	  `es-find id=xxx | grep result_root`
	  `cp /srv/$result_root ./`

	- https://compass-ci/jobs/ 页面搜索 `id=xxx`, 点击`$job_stat`列 获得`result_root_url`
	  下载该url(对应是文件夹)
   2. 获得`$result_root` 后， 运行 `compass-ci/sbin/result2stats $result_root`, 可见具体报错，针对报错去修复问题


### 常见问题
- ES DB/web中发现某个job没有job['stats']
  问题通常发生在 `results2stats $result_root` 优先本地调试

- ES DB/web 中发现某个job['stats']不完整
  1. `ll $result_root` 发现生成$result_root/stats.json 时间比`$result_root/$log` 早。
     通常为job运行超时，调度器提前让任务结束。因此需要将job['runtime']时间改大一些
     当前任务使用 服务端工具：
	`re-stats id=xxx`： 重新生成stats.json
	`re-stats group_id=xxx`: 批量重新生成一批job的stats.json
     re-stats 工具需要服务端器的$result_root 的读写权限。
     由于安全问题未解决，re-stats目前不能开放给客户端使用

  2. 如果是其他原因造成，使用本地调试或分析服务器日志

