# submit 命令详解

### 前提条件

已经按照[本地安装compass-ci客户端](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/install-cci-client.md )完成安装

### 概述

submit 命令的作用是提交测试任务。该命令提供了多个选项帮助用户更灵活的提交任务，您可以在命令行直接输入 summit 命令来查看帮助信息，并根据实际需求灵活使用。

### 基本用法

测试任务以 yaml 文件的方式提交，因此，您需要事先准备好测试任务的 yaml 文件（本文以 iperf.yaml 为例）。

若您的yaml文件不包含testbox字段，直接提交将会报错：

```shell
hi8109@account-vm ~% submit iperf.yaml
submit iperf.yaml failed, got job_id=0, error: Missing required job key: 'testbox'
```

因为testbox是必填字段，您可以在 yaml 文件中添加 testbox 字段，或使用如下命令：

```shell
hi8109@account-vm ~% submit iperf.yaml testbox=vm-2p8g
submit iperf.yaml, got job_id=z9.173924
```

testbox 字段的值指定需要的测试机，可以使用 `ll` 命令查看 `lkp-tests/hosts` 路径下的可选测试机。如下所示：

```shell
hi8109@account-vm ~/lkp-tests/hosts% ll
total 120K
-rw-r--r--. 1 root root  76 2020-11-02 14:54 vm-snb
-rw-r--r--. 1 root root  64 2020-11-02 14:54 vm-pxe-hi1620-2p8g
-rw-r--r--. 1 root root  64 2020-11-02 14:54 vm-pxe-hi1620-2p4g
-rw-r--r--. 1 root root  64 2020-11-02 14:54 vm-pxe-hi1620-2p1g
-rw-r--r--. 1 root root  64 2020-11-02 14:54 vm-pxe-hi1620-1p1g
-rw-r--r--. 1 root root  75 2020-11-02 14:54 vm-hi1620-2p8g
-rw-r--r--. 1 root root  75 2020-11-02 14:54 vm-hi1620-2p4g
-rw-r--r--. 1 root root  75 2020-11-02 14:54 vm-hi1620-2p1g
-rw-r--r--. 1 root root  75 2020-11-02 14:54 vm-hi1620-1p1g
-rw-r--r--. 1 root root  61 2020-11-02 14:54 vm-2p8g-pxe
-rw-r--r--. 1 root root  61 2020-11-02 14:54 vm-2p8g
-rw-r--r--. 1 root root  61 2020-11-02 14:54 vm-2p4g-pxe
-rw-r--r--. 1 root root  61 2020-11-02 14:54 vm-2p4g
-rw-r--r--. 1 root root  61 2020-11-02 14:54 vm-2p1g-pxe
-rw-r--r--. 1 root root  61 2020-11-02 14:54 vm-2p1g
-rw-r--r--. 1 root root  61 2020-11-02 14:54 vm-1p1g-pxe
-rw-r--r--. 1 root root  61 2020-11-02 14:54 vm-1p1g
-rw-r--r--. 1 root root  14 2020-11-02 14:54 taishan200-2280-2s64p-256g
-rw-r--r--. 1 root root 497 2020-11-02 14:54 lkp-skl-d01
-rw-r--r--. 1 root root 574 2020-11-02 14:54 lkp-ivb-d04
-rw-r--r--. 1 root root 606 2020-11-02 14:54 lkp-ivb-d02
-rw-r--r--. 1 root root 384 2020-11-02 14:54 lkp-ivb-d01
-rw-r--r--. 1 root root 388 2020-11-02 14:54 lkp-hsw-d01
-rw-r--r--. 1 root root 385 2020-11-02 14:54 lkp-bdw-de1
-rw-r--r--. 1 root root  11 2020-11-02 14:54 dc-8g
-rw-r--r--. 1 root root  11 2020-11-02 14:54 dc-4g
-rw-r--r--. 1 root root  11 2020-11-02 14:54 dc-2g
-rw-r--r--. 1 root root  11 2020-11-02 14:54 dc-1g
-rw-r--r--. 1 root root  13 2020-11-02 14:54 2288hv5-2s64p
-rw-r--r--. 1 root root  74 2020-11-02 14:54 vm-snb-i386
```

>![](./../public_sys-resources/icon-note.gif) **说明：**
>
>使用 "=" 更新 yaml 中的字段，"=" 在命令行中的位置不同优先级不同：.
> * submit iperf.yaml testbox=vm-2p8g  命令中 "=" 定义在 yaml 文件之后，则 "=" 的优先级高于 yaml 文件,testbox=vm-2p8g 会覆盖 yaml 文件中已经定义的 testbox 字段。
> * submit testbox=vm-2p8g iperf.yaml  命令中 "=" 定义在 yaml 文件之前，则 "=" 的优先级低于 yaml 文件,testbox=vm-2p8g 不会覆盖 yaml 文件中已经定义的 testbox 字段，只有当 yaml 文件中不存在 testbox 字段才会赋值。



### 高级用法

submit 命令的选项如下所示：

```shell
hi8109@account-vm ~% submit
Usage: submit [options] job1.yaml job2.yaml ...
       submit test jobs to the scheduler

options:
    -s, --set 'KEY: VALUE'           add YAML hash to job
    -o, --output DIR                 save job yaml to DIR/
    -a, --auto-define-files          auto add define_files
    -c, --connect                    auto connect to the host
    -m, --monitor                    monitor job status: use -m 'KEY: VALUE' to add rule
        --my-queue                   add to my queue
```

* **-s的用法**

    使用 -s 'KEY:VALUE' 参数可以将键值对更新到提交的任务当中。示例如下所示：
    ```
    submit -s 'testbox: vm-2p8g' iperf.yaml
    ```


    * 如果 iperf.yaml 中不存在 testbox：vm-2p8g ，最终提交的任务将会加上该信息。
    * 如果 iperf.yaml 中存在 testbox 字段，但是值不为 vm-2p8g ，最终提交的任务中 testbox 的值将会被替换为vm-2p8g。

* **-o的用法**

    使用-o DIR 命令可以将最终生成的yaml文件保存到指定目录 DIR 下。示例如下所示：

    ```
    submit -o ~/iperf.yaml testbox=vm-2p8g
    ```

    运行命令之后会在指定目录生成经过 submit 处理过的 yaml 文件。

* **-a的用法**

    如果你的测试用例对客户端的lkp-tests 做了更改，需要使用 -a 选项来适配。将客户端的 lkp-tests 下做的更改，同步到服务端，并在测试机上生成你的测试脚本。
    示例命令如下：

    ```
    submit -a iperf.yaml testbox=vm-2p8g
    ```

    ```
    可添加的文件及目录：lkp-tests/*/$program ， lkp-tests/*/$program/* ， lkp-tests/*/*/$program ， lkp-tests/*/*/$program/* 。
    $program 的值是 $suite ， $suite-dev ， $suite.aarch64 或 $suite.x86_64 。
    当 suite 为 makepkg ， makepkg-deps ， pack-deps ， cci-makepkg 或 cci-depends 时，$program = $benchmark 。
    ```

* **-m的用法**

    使用 -m 参数可以启动任务监控功能，并将任务执行过程中的各种状态信息打印到控制台上，方便用户实时监控测试任务的执行过程。
    示例命令如下：

    ```
    submit -m iperf.yaml testbox=vm-2p8g
    ```

    控制台显示如下：

    ```shell
    hi8109@account-vm ~% submit -m iperf.yaml testbox=vm-2p8g
    submit iperf.yaml, got job_id=z9.173923
    query=>{"job_id":["z9.173923"]}
    connect to ws://172.168.131.2:11310/filter
    {"job_id":"z9.173923","message":"","job_state":"submit","result_root":"/srv/result/iperf/2020-11-30/vm-2p8g/openeuler-20.03-aarch6
    {"job_id": "z9.173923", "result_root": "/srv/result/iperf/2020-11-30/vm-2p8g/openeuler-20.03-aarch64/tcp-30/z9.173923", "job_state
    {"job_id": "z9.173923", "job_state": "boot"}
    {"job_id": "z9.173923", "job_state": "download"}
    {"time":"2020-11-30 20:28:16","mac":"0a-f5-9f-83-62-ea","ip":"172.18.192.21","job_id":"z9.173923","state":"running","testbox":"vm-
    {"job_state":"running","job_id":"z9.173923"}
    {"job_state":"post_run","job_id":"z9.173923"}
    {"start_time":"2020-11-30 12:25:15","end_time":"2020-11-30 12:25:45","loadavg":"1.12 0.38 0.14 1/105 1956","job_id":"z9.173923"}
    {"job_state":"finished","job_id":"z9.173923"}
    {"job_id": "z9.173923", "job_state": "complete"}
    {"time":"2020-11-30 20:28:54","mac":"0a-f5-9f-83-62-ea","ip":"172.18.192.21","job_id":"z9.173923","state":"rebooting","testbox":"v
    {"job_id": "z9.173923", "job_state": "extract_finished"}
    connection closed: normal
    ```

* **-c的用法**

    -c 参数需要搭配 -m 参数来使用，可以使申请设备的任务实现自动登入功能。

    示例命令如下：

    ```
    submit -m -c borrow-1h.yaml testbox=vm-2p8g
    ```
    当我们提交一个申请设备的任务后，会获取到返回的登陆信息，如 `ssh ip -p port`，添加 -c 参数之后不需要我们手动输入 ssh 登陆命令来进入执行机。

	控制台显示如下：

    ```shell
    hi8109@account-vm ~% submit -m -c borrow-1h.yaml testbox=vm-2p8g
    submit borrow-1h.yaml, got job_id=z9.173925
    query=>{"job_id":["z9.173925"]}
    connect to ws://172.168.131.2:11310/filter
    {"job_id":"z9.173925","message":"","job_state":"submit","result_root":"/srv/result/borrow/2020-11-30/vm-2p8g/openeuler-20.03-aarch
    {"job_id": "z9.173925", "result_root": "/srv/result/borrow/2020-11-30/vm-2p8g/openeuler-20.03-aarch64/3600/z9.173925", "job_state"
    {"job_id": "z9.173925", "job_state": "boot"}
    {"job_id": "z9.173925", "job_state": "download"}
    {"time":"2020-11-30 20:35:04","mac":"0a-24-5d-c8-aa-d0","ip":"172.18.101.4","job_id":"z9.173925","state":"running","testbox":"vm-2
    {"job_state":"running","job_id":"z9.173925"}
    {"job_id": "z9.173925", "state": "set ssh port", "ssh_port": "50200", "tbox_name": "vm-2p8g.taishan200-2280-2s48p-256g--a52-7"}
    Host 172.168.131.2 not found in /home/hi8109/.ssh/known_hosts
    Warning: Permanently added '[172.168.131.2]:50200' (ECDSA) to the list of known hosts.
    Last login: Wed Sep 23 11:10:58 2020


    Welcome to 4.19.90-2003.4.0.0036.oe1.aarch64

    System information as of time:  Mon Nov 30 12:32:04 CST 2020

    System load:    0.50
    Processes:      105
    Memory used:    6.1%
    Swap used:      0.0%
    Usage On:       89%
    IP address:     172.17.0.1
    Users online:   1



    root@vm-2p8g ~#
    ```

    已经成功登陆执行机。

