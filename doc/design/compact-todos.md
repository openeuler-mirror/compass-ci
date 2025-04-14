# 瘦身计划

Tasks roughtly in priority order.

## 轻量部署及测试
a light deploy script for
- developer
- selftest
- simple customer cases
ship modules: scheduler, result-webdav, srv-http, data-api, manticore-search

## cci客户端 易用性增强
cci: 能力改进、易用性增强、add common/useful query use cases
- 活跃测试机: scheduler api
- stage=submit jobs count by user/testbox/suite
- last Nday jobs list for one user/testbox/suite
- last Nday jobs count by user/testbox/suite
- last Nday jobs total time by user/testbox/suite
- last N failed jobs & failed cause
- 自己的job的状态（当前剩余的job，在执行的job）
- 所有的机器状态（哪些掉线，什么时候掉线，哪些在执行，跑了多少任务）

## lifecycle 梳理
lifecycle: make it clear and correct
- only handle hw machine: reboot machine on dmesg oops
- vm dmesg directly handled by qemu.sh
- other lifecycle timeout/retry handled by scheduler

## 调度器瘦身
- scheduler: 单进程化，remove scheduler-nginx dispatcher
- scheduler: merge extract-stats, post-extract services

- scheduler: config option to enable: manticore search db
- scheduler: config option to remove dependency: ES
- scheduler: enable IO on manticore search db

## 调度器改进
- scheduler: add multi-queue scheduling, local cache jobs, hosts
- scheduler: add general `api/watch_jobs`

- scheduler: config option to remove dependency: etcd
- scheduler: remove redis dependency

## 多机测试
- if-role
- switch 多机测试专用wait机制 to after-milestone and `api/watch_jobs`
- networking

## 数据库瘦身

ES占用内存太大，不利于小客户小场景使用。

## ES => manticore-search 瘦身可行性
- ES切manticore-search较简单，有兼容 JSON API
- 主要工作为适配`es_cient`，支持双数据库，either db can be turned on/off by config option

## manticore-search => mariadb 瘦身可行性
- 主要障碍是JSON query语句，不过基本可以改写为SELECT语句，建议试试chatGPT辅助转换。`web_backend.rb`还有前端代码里有不少JSON query语句。未来别新增json query了。select更好用，兼容性更好。
- mariadb可以建多个index。full-text index和JSON类型也有
- 偏静态index。所以`pp.*.*`, `ss.*.*`会有问题。关键是`ss.*.*`在bisect会用到，不过也有办法。在写表前，把`ss.*.commit`值合入固定字段`ss_all_commit`，把`ss.*.config=val`合入`ss_config_kv`，把`pp.*.*=val`合入`pp_kv`。`ss_all_commit/ss_config_kv/pp_kv`都建full-text index即可。在业务层转换为对以上固定字段的full-text搜索。
