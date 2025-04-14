# 多机测试中，用 if-role 选择执行节点

- 如果job包含cluster字段，则为多机测试
- 取消原有的if role块，它破坏了job yaml的结构
- 加一个'if-role'字段，作为各个monitor/setup/daemon/program script的多机测试属性
- if-role 取值: 空格分隔的一个或多个roles
- if-role 缺省值:
    monitor.xxx.if-role: server
    setup.xxx.if-role: server
    daemon.xxx.if-role: server
    program.xxx.if-role: client

## example 1

```yaml
if role server:
  daemon.netserver-sequence:

if role client:
  program.netperf-sequence:
    runtime: 300
    testnames: TCP_RR UDP_RR TCP_CRR TCP_STREAM UDP_STREAM

# for kernel PGO feedback compilation and processing of sampled data
program.kernel-profiling-process:
```
=>
```yaml
daemon.netserver-sequence:

program.netperf-sequence:
  runtime: 300
  testnames: TCP_RR UDP_RR TCP_CRR TCP_STREAM UDP_STREAM

# for kernel PGO feedback compilation and processing of sampled data
program.kernel-profiling-process:
  if-role: server client
```

## example 2

```yaml
if role server:
  setup.disk: 1HDD
  setup.fs: ext4
  daemon.nfsd:

if role client:
  setup.fs: nfsv4
  program.dd:
    bs: 4k
    nr_threads: 2dd
```

=> remove 'if role' level =>

```yaml
setup:
  disk:
      nr_hdd: 1
      if-role: server
  fs:
      fs_type: ext4
      if-role: server
  fs-0:
      fs_type: nfsv4
      if-role: client

daemon.nfsd:
      if-role: server

program.dd:
      bs: 4k
      nr_threads: 2dd
      if-role: client
```

## example 3

mugen-iperf3.yaml
```
setup.passwd:

daemon.sshd:

program.mugen:
    testsuite: iperf3
```

## scheduler 实现

on first job consume, split cluster job:

```
    # common
    cluster_jobs:
        jobid1: roles=[server]
        jobid2: roles=[client]
        jobid3: roles=[client]
```
