## Compass-CI                                                                         


### 关于 Compass-CI

Compass-CI 是一个可持续集成的开源软件平台。为开发者提供针对上游开源软件（来自 Github, Gitee, Gitlab 等托管平台）的测试服务、登录服务、故障辅助定界服务和基于历史数据的分析服务。Compass-CI 基于开源软件 PR 进行自动化测试(包括构建测试，软件包自带用例测试等)，构建一个开放、完整的测试系统。


### 功能介绍 

**测试服务**

Compass-CI 监控很多开源软件 git repos，一旦检测到代码更新，会自动触发[自动化测试](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/test-guide/test-oss-project.zh.md)，开发者也可以[手动提交测试 job](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/job/submit/submit-job.zh.md)。

**调测环境登录**

使用 SSH [登录测试环境进行调测](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/user-guide/log-in-machine-debug.md)。

**测试结果分析**

通过 [Web](https://compass-ci.openeuler.org) 接口，对历史测试结果进行分析和比较。

**测试结果复现**

一次测试运行的所有决定性参数会在 job.yaml 文件中保留完整记录。
重新提交该 job.yaml 即可在一样的软硬件环境下，重跑同一测试。

**辅助定位**

如果出现新的 error id，就会自动触发bisect，定位引入该 error id 的 commit。

## Getting started

**自动化测试**

1. 添加待测试仓库 URL 到 [upstream-repos](https://gitee.com/wu_fengguang/upstream-repos.git) 仓库，[编写测试用例](https://gitee.com/wu_fengguang/lkp-tests/blob/master/doc/add-testcase.md)并添加到 [lkp-tests](https://gitee.com/wu_fengguang/lkp-tests) 仓库, 详细流程请查看[这篇文档](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/test-guide/test-oss-project.zh.md)。

2. 执行 git push 命令更新仓库，自动触发测试。

3. 在网页中[查看](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/result/browse-results.zh.md)和[比较](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/result/compare-results.zh.md)测试结果 web: https://compass-ci.openeuler.org/jobs

**自动化测试示例**

如何在 compass-ci 上自动化测试我的仓库 https://github.com/baskerville/backlight ?
1. Fork upstream-repos 仓库（https://gitee.com/wu_fengguang/upstream-repos） 并 git clone 到本地
2. 新建文件 b/backlight/backlight，内容为：

    ```
    ---
    url:
    - https://github.com/baskerville/backlight
    ```

3. 添加测试用例

   测试用例可以自己编写并添加到 lkp-tests 仓库,

   也可以直接使用 lkp-tests 仓库（https://gitee.com/wu_fengguang/lkp-tests ）的 jobs 目录下已有的测试用例。

   在 backlight 文件所在目录增加 DEFAULTS 文件并添加配置信息

    ```
    submit:
    - command: testbox=vm-2p16g os=openeuler os_version=20.03 os_mount=cifs os_arch=aarch64 api-avx2neon.yaml
      branches:
      - master
      - next
    - command: testbox=vm-2p16g os=openeuler os_version=20.03 os_mount=cifs os_arch=aarch64 other-avx2neon.yaml
      branches:
      - branch_name_a
      - branch_name_b
    ```

4. 通过 Pull Request 命令将新增的文件提交到 upstream-repos 仓库

**手动提交测试任务**

1. [安装 Compass-CI 客户端](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/user-guide/install-cci-client.md)。
2. [编写测试用例](https://gitee.com/wu_fengguang/lkp-tests/blob/master/doc/add-testcase.md), [手动提交测试任务](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/job/submit/submit-job.zh.md)。
3. 在网页中[查看](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/result/browse-results.zh.md)和[比较](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/result/compare-results.zh.md)测试结果 web: https://compass-ci.openeuler.org/jobs

**手动提交测试任务示例**

如何向 compass-ci 提交一个测试任务？
1. 已经按照[本地安装compass-ci客户端](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/user-guide/install-cci-client.md )
完成安装
2. 测试任务以 yaml 文件的方式提交，因此，您需要事先准备好测试任务的 yaml 文件

   可以直接使用 lkp-tests 仓库（https://gitee.com/wu_fengguang/lkp-tests ）的 jobs 目录下已有的测试用例

   以 iperf.yaml 为例：

    ```yaml
    suite: iperf
    category: benchmark

    runtime: 300s

    cluster: cs-localhost

    if role server:
      iperf-server:

    if role client:
      iperf:
        protocol:
        - tcp
        - udp
    ```

3. 使用 submit 命令提交 iperf.yaml 测试任务

    ```shell
    hi8109@account-vm ~% submit iperf.yaml testbox=vm-2p8g
    submit iperf.yaml, got job_id=z9.173924
    submit iperf.yaml, got job_id=z9.173925
    ```

**登录测试环境**

1. 向 compass-ci-robot@qq.com 发送邮件[申请账号](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/user-guide/apply-account.md)。
2. 根据邮件反馈内容完成环境配置。
3. 在测试任务中添加 sshd 字段，提交相应的任务，[登录测试环境](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/user-guide/log-in-machine-debug.md)。

**登录测试环境示例**

如果我提交的一个测试用例执行失败了，我想要登录到执行机内部进行调测该怎么操作？

我的测试用例是 spinlock.yaml：

   ```yaml
   suite: spinlock
   category: benchmark
   nr_threads:
   - 1
   spinlock:
   ```

1. 若我想在运行 spinlock 测试脚本之前登录执行机，yaml 需要做如下更改：

    ```yaml
    suite: spinlock
    category: benchmark
    nr_threads:
    - 1

    ssh_pub_key: <%= File.read("#{ENV['HOME']}/.ssh/id_rsa.pub").chomp rescue nil %>
    sshd:
    runtime: 1h
    sleep:

    spinlock:
    ```

   ssh_pub_key: 用于将本地的 pub_key 携带上来，用于免密登录

   sshd: 表示执行机需要运行 lkp-tests/damon/sshd 脚本，将会建立 sshr 反向隧道，用于 ssh 登录

   runtime: 表示 sleep 的时间

   sleep: 放在 spinlock 前面，表示先执行 sleep，sleep 1h 之后再执行 spinlock 脚本

2. 若我想在 spinlock 测试失败之后登录执行机，yaml 需要做如下更改：

    ```yaml
    suite: spinlock
    category: benchmark
    nr_threads:
    - 1
    spinlock:

    on_fail:
        sshd:
        sleep: 1h
    ```

   on_fail: 将在测试用例执行失败之后运行

3. 使用 submit -m -c spinlock.yaml 提交修改后的 yaml 文件

   机器建立好 sshd 隧道之后会自动连接登录执行机

    ```shell
    hi8109@account-vm ~% submit -m -c spinlock.yaml
    submit_id=6f2d11df-2198-41e9-a0e6-6aa67f9b46e2
    submit spinlock.yaml, got job id=z9.10155176
    query=>{"job_id":["z9.10155176"]}
    connect to ws://api.compass-ci.openeuler.org:20001/filter
    {"level_num":2,"level":"INFO","time":"2021-09-17T17:21:03.436+0800","from":"172.17.0.1:40014","message":"access_record","status_code":200,"method":"GET","resource":"/job_initrd_tmpfs/z9.10155176/job.cgz","job_id":"z9.10155176","job_state":"download","api":"job_initrd_tmpfs","elapsed_time":0.465723,"elapsed":"465.72µs"}

    The dc-8g testbox is starting. Please wait about 30 seconds
    {"level_num":2,"level":"INFO","time":"2021-09-17T17:21:08+0800","mac":"02-42-ac-11-00-03","ip":"","job_id":"z9.10155176","state":"running","testbox":"dc-8g.taishan200-2280-2s48p-256g--a67-14","status_code":200,"method":"GET","resource":"/~lkp/cgi-bin/lkp-wtmp?tbox_name=dc-8g.taishan200-2280-2s48p-256g--a67-14&tbox_state=running&mac=02-42-ac-11-00-03&ip=&job_id=z9.10155176","api":"lkp-wtmp","elapsed_time":19.024787,"elapsed":"19.02ms"}
    {"level_num":2,"level":"INFO","time":"2021-09-17T17:21:12.622+0800","from":"172.17.0.1:42838","message":"access_record","status_code":200,"method":"GET","resource":"/~lkp/cgi-bin/lkp-jobfile-append-var?job_file=/lkp/scheduled/job.yaml&job_id=z9.10155176&job_state=running","job_id":"z9.10155176","api":"lkp-jobfile-append-var","elapsed_time":74.76464,"elapsed":"74.76ms","job_state":"running","job_stage":"running"}
    {"level_num":2,"level":"INFO","time":"2021-09-17T17:21:12.982+0800","tbox_name":"dc-8g.taishan200-2280-2s48p-256g--a67-14","job_id":"z9.10155176","ssh_port":"21063","message":"","state":"set ssh port","status_code":200,"method":"POST","resource":"/~lkp/cgi-bin/report_ssh_info","api":"report_ssh_info","elapsed_time":0.414042,"elapsed":"414.04µs"}
    ssh root@172.168.131.2 -p 21063 -o StrictHostKeyChecking=no -o LogLevel=error
    root@dc-8g.compass-ci.net ~#
    ```

## Contributing to Compass-CI

我们非常欢迎有新的贡献者，我们也很乐意为我们的贡献者提供一些指导，Compass-CI 主要是使用 Ruby 开发的一个项目，我们遵循 [Ruby 社区代码风格](https://ruby-china.org/wiki/coding-style)。如果您想参与社区并为 Compass-CI 项目做出贡献，[这个页面](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/development/learning-resources.md)将会提供给您更多信息，包括 Compass-CI 所使用的所有语言和工具等。

## Website

所有的测试结果，已加入 Compass-CI 平台的开源软件清单，历史测试结果比较都可以在我们的官网 [Website](https://compass-ci.openeuler.org) 上找到。

## 加入我们

您可以通过以下的方式加入我们：
  - 您可以加入我们的 [mailing list](https://mailweb.openeuler.org/postorius/lists/compass-ci.openeuler.org/)

欢迎您跟我们一起：
  - 增强 git bisect 能力
  - 增强数据分析能力
  - 增强数据结果可视化能力

## 了解更多

[了解更多](./doc/)
