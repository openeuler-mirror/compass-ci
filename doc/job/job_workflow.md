[TOC]

# 前提条件：
    
已经按照compass-ci/doc/user-guide/install-cci-client.md本地安装了compass-ci客户端。
下面的测试环境中就会有$LKP_SRC这个变量。

# job流程概述
一个测试任务就是一个job，我们提交一个任务测试，就是用$LKP_SRC/sbin/submit命令提交一个yaml文件。格式就是:
```
submit job.yaml   
```

job从提交到执行经过以下几个步骤：

    准备job yaml（可以自己写，也可以用$LKP_SRC/jobs下的） 
    -> 提交job yaml 
    -> 本地自动对job yaml进行处理（解析、修改、扩充等） 
    -> job提交到调度器 
    -> 调度器对job进行处理（解析、更新等） 
    -> job分配到测试机上执行

## job yaml示例
这里提交一个yaml: $LKP_SRC/jobs/netperf-send_size.yaml, 这里使用这个文件前半部分测试，内容如下:
```
suite: netperf
category: benchmark

# upto 90% CPU cycles may be used by latency stats
disable_latency_stats: 1

set_nic_irq_affinity: 1

ip:
    - ipv4
  # - ipv6

runtime: 300
nr_threads:
    - 1

cluster: cs-localhost

if role server:
  netserver:

if role client:
  netperf:
    test:
    - TCP_RR
    - UDP_RR
    - TCP_CRR
```

## 提交job
建议阅读一下compass-ci/doc/job/submit/submit-job.zh.md，了解submit的一些用法，先来介绍一个比较有用功能"submit -o DIR"
```
submit job.yaml -o DIR
```
这常用于调试，不会提交任务，但是会在指定目录生成经过 submit 处理过的 yaml 文件，这个文件就是我们最终会提交的文件，方便我们来调试。

提交任务：
```
~/lkp-tests% submit jobs/netperf-send_size.yaml -o ~/tmp
submit_id=80e4b6d8-029b-4dd3-b317-cb25a9d5bab6
jobs/netperf-send_size.yaml => /home/xxx/tmp/netperf-send_size-cs-localhost-ipv4-1-300-TCP_RR.yaml
jobs/netperf-send_size.yaml => /home/xxx/tmp/netperf-send_size-cs-localhost-ipv4-1-300-UDP_RR.yaml
jobs/netperf-send_size.yaml => /home/xxx/tmp/netperf-send_size-cs-localhost-ipv4-1-300-TCP_CRR.yaml
```
可以看到这个job yaml分解成两个job准备提交，这是在lkp-tests测试框架内进行了一系列的处理，然后才会把这些处理过的yaml提交给调度器。

去掉-o和后面的参数，就是真实提交两个任务到调度器了。

## 调度器处理
调度器对job进行处理，保存在数据库里，并把这个job的id放在指定的队列中，等待消费这个队列的测试机来获取这个job。

## 测试机请求任务
- 请求的任务是和启动测试机的过程一起的，测试启动使用ipxe方式，这个启动过程可以参考文档compass-ci/doc/install/cci-use-ipxe-to-boot.md。
- 测试机提前在数据库里注册自己的测试机对应相应的队列，然后测试机就可以根据这个队列来获取job的id。
- 然后根据job的id获取任务具体的内容。
- 根据job的内容生成一些测试文件(job.yaml, job.sh等)打包成job.cgz下发给测试机

job.sh文件这个文件就是在测试机上执行的测试文件，job.sh的生成命令如下：
```
~/lkp-tests% $LKP_SRC/sbin/job2sh /home/xxx/tmp/netperf-send_size-cs-localhost-ipv4-1-300-TCP_CRR.yaml

#!/bin/sh

export_top_env()
{
        export suite='netperf'
        export category='benchmark'
        export disable_latency_stats=1
        export set_nic_irq_affinity=1
        export ip='ipv4'
        export runtime=300
        export nr_threads=1
        export cluster='cs-localhost'
        export job_origin='jobs/netperf-send_size.yaml'
        export node_roles='server client'
        export submit_id='ad20a0bc-d9de-4e7c-a4d4-e95e797d772a'
        export SCHED_HOST='xxxx'
        export SCHED_PORT=3000
        export lab='crystal'
        export os_mount='local'
        export testbox='dc-8g'
        export tbox_group='dc-8g'
        export arch='aarch64'
        export memory='8g'
        export os_arch='aarch64'
        ...

        [ -n "$LKP_SRC" ] ||
        export LKP_SRC=/lkp/${user:-lkp}/src
}
run_job()
{
        echo $$ > $TMP/run-job.pid

        . $LKP_SRC/lib/http.sh
        . $LKP_SRC/lib/job.sh
        . $LKP_SRC/lib/env.sh

        export_top_env

        run_monitor $LKP_SRC/monitors/wrapper kmsg
        ......
        ......
        run_monitor $LKP_SRC/monitors/wrapper mpstat
        run_monitor lite_mode=1 $LKP_SRC/monitors/no-stdout/wrapper perf-profile

        if role server
        then
                start_daemon $LKP_SRC/daemon/netserver
        fi

        if role client
        then
                run_test test='TCP_CRR' $LKP_SRC/tests/wrapper netperf
        fi
}
......  
```
## 测试机执行任务
测试机请求到任务以后，在开机时启动一个lkp-bootstrap服务，这个服务中包含执行任务的进程。
```
 systemctl status lkp-bootstrap

● lkp-bootstrap.service - LKP bootstrap
   Loaded: loaded (/usr/lib/systemd/system/lkp-bootstrap.service; enabled; vendor preset: disabled)
   Active: active (running) since Sat 2021-12-25 11:06:49 CST; 3h 38min ago
 Main PID: 3453 (lkp-bootstrap)
    Tasks: 20
   Memory: 5.0G
   CGroup: /system.slice/lkp-bootstrap.service
           ├─  3453 /bin/sh /etc/init.d/lkp-bootstrap
           ├─  3455 /bin/sh /lkp/lkp/src/bin/lkp-setup-rootfs
           ├─  3469 tail -f /tmp/stdout
           ├─  3470 sed -u -r s/^(.{0,900}).*$/<5>\1/
           ├─  3471 tail -f /tmp/stderr
           ├─  3472 sed -u -r s/^(.{0,900}).*$/<3>\1/
           ├─ 12967 /bin/sh /lkp/lkp/src/bin/run-lkp /lkp/scheduled/job.yaml
           ├─ 12971 tail -n 0 -f /tmp/stdout
           ├─ 12972 tail -n 0 -f /tmp/stderr
           ├─ 12973 tail -n 0 -f /tmp/stdout /tmp/stderr
           ├─ 13001 /bin/sh /lkp/scheduled/job.sh run_job
           ├─ 63127 dmesg --follow --decode
           ├─ 63129 vmstat --timestamp -n 100
           ├─ 63131 /bin/sh /lkp/lkp/src/monitors/meminfo
           ├─ 63145 cat /tmp/lkp/fifo-kmsg
           ├─ 63148 cat /tmp/lkp/fifo-heartbeat
           ├─ 63152 gzip-meminfo -c
           ├─ 63688 sleep 8640000
           ├─ 63698 tee -a /tmp/lkp/result/sleep
           └─264564 /lkp/lkp/src/bin/event/wait post-test --timeout 1
```
"/bin/sh /lkp/scheduled/job.sh run_job" 这个进程就是运行测试脚本的入口


下面我们具体介绍一下这几个步骤。
# 1. job yaml的写法
job yaml里会有很多key-value的值, 这里的key-value会有几种类型：
- 头部标识字段
- 脚本名字段
- 必须的参数字段
- 非必须的参数字段
- 其他功能的字段

通过以下几个例子介绍一下各个字段。

## 1.1 头部标识字段(必须)
一般位于job 文件的开始部分，包含一些基础的描述信息，主要有 suite 和 category
```
suite: netperf       \\测试套名称字段: 根据自己测试的对象命令
category: benchmark  \\测试类型主要有两种：benchmarch性能测试 functional功能测试
                     \\不同的测试类型主要影响是会在测试的时候监控项,测试项见lkp-tests/include/category/
```

## 1.2 脚本名字段(必须)
job yaml中写入了以下路径中脚本的脚本名，就会在测试时执行这个脚本
```
$LKP_SRC/setup     # 用于测试程序之前，需要提前进行的程序，比如磁盘的挂载与配置
$LKP_SRC/monitors  # 监控程序
$LKP_SRC/daemon    # 用于测试开始前，启动需要后台运行的程序，比如启动mysql的server
$LKP_SRC/tests     # 测试程序
```

示例：
```
netserver:
netperf:
  runtime: 10s
  test:
  - TCP_STREAM
  send_size:
  - 1024
```
这里先启动了一个netserver后台进程（脚本位于$LKP_SRC/daemon下），然后启动一个netperf测试程序（脚本位于$LKP_SRC/tests下），netperf下的key-value，作为参数传入这个脚本。

> 需要注意的几点：
>    1. 即使是不同目录下的脚本名也不能相同
>    2. 脚本需要可执行权限
>    3. 如果yaml里写入同一个路径（如$LKP_SRC/tests/）的下的多个脚本，测试时执行的优先级对应在yaml中顺序
>    4. 如果yaml里写入不同路径的多个脚本名，测试时执行的优先级为 monitors脚本>setup脚本>daemon脚本>tests脚本。这一步是在调用job2sh的完成的（参考$LKP_SRC/lib/job2sh.rb的to_shell函数）

## 1.3 必须的参数字段
提交任务有些变量是必须填的，这部分变量都可以在compass-ci/doc/job/fields下了解到，下面我们介绍几个常用的字段：
    
- testbox: 定义测试机的类型和规格

    可以不指定，默认会是dc-8g,也就是默认的测试机类型是使用docker。
    
    类型主要有三种：容器('dc-'开头）、虚拟机('vm-'开头)、物理机(自定义)。
    
    提交的时候会根据testbox的值（假设是dc-8g）去加载dc-8g这个host文件，这个文件的内容也是key-value，合并成一个文件提交。
    
    如果有多个host文件存在，那会加载哪一个呢？我们会在下面部分介绍加载优先级。

> testbox还有一个作用就是作为任务的队列，例如testbox=vm-2p8g, arch=aarch64这样设置时，默认这个任务的队列queue是vm-2p8g.aarch64


- os：定义系统的类型
    
    testbox默认是dc-8g，对应默认os=centos7以及os_version=centos7, os_mount=container，目前支持的os类型可以参考compass-ci/doc/job/submit/supported-testbox-matrix.md

- SCHED_HOST: 提交到的调度器
- SCHED_PORT: 调度器的端口
- lab: 测试机所在的集群


## 1.4 非必须的参数字段
一般是用户自定义的字段

字段的变量会在测试机上作为环境变量使用,会影响测试用例里的值。

但是如果测试用例又定义这个变量，那么已测试用例的值为准。
```
mysql_port: 3309          \\普通字段，程序中可能会用到这个变量
```

## 1.5 secrets字段
这个字段用于一些敏感的信息，不想要展示出来，提交以后job.yaml目前是公开的。
用法是在提交时,job yaml中写入：
```
secrets:
    mysql_password: xxx
```
这样在测试端提交本地信息时，
```
client -> submit 
            -> sched ： 调度器会去处理这个字段，单独保存在数据库，并在job中删除这个字段。
                -> testbox：获取任务时，从数据库读取，保存到secrets.yaml使用
这样在对外的result目录下，job.sh和job.yaml都没有这个字段。
```
在测试时使用 $secrets_mysql_password 变量即可，也就是所有secrets字段均加上前缀secrets_。

## 1.6 on_fail字段
on_fail字段是在任务测试出错的时候，执行on_fail下的程序。比如$LKP_SRC/jobs/send-email-on-fail.yaml:
```
on_fail:
    send_email:
        subject: job_failed
```
提交的时候带上这个yaml： submit job.yaml -i send-email-on-fail.yaml
那么在任务失败的时候就会发送一封邮件通知到任务提交者。

当然也可以在on_fail下加上sleep字段,比如
```
on_fail:
    sleep: 1h
```
这样任务失败后，有一个小时的时间可以登录到测试机上调试


# 2. job提交                      
## 2.1 关于提交命令submit
我们已经有一个完整的文档关于submit命令的详解，参考compass-ci/doc/job/submit/submit-job.zh.md

## 2.2 提交任务时加载的文件
### 提交的yaml
- 提交的时候如果job.yaml是绝对路径的文件，那么就使用这个文件。
- 如果不是绝对路径的文件，那么就在当前目录下找这个文件。
- 如果当前目录也没有这个文件，那么就去$LKP_SRC/jobs下找这个文件。
- 如果最后还没找到，就会报错。

### 系统配置文件：/etc/compass-ci/defaults/*.yaml
### 用户配置文件：~/.config/compass-ci/defaults/*.yaml
- 用户配置优先级高于系统配置
- 配置文件里一般放置调度器的信息(SCHED_HOST，SCHED_PORT等)
- 申请测试账户成功时，生成的账户信息(lab， 用户等)放置在用户配置目录下的account.yaml

### lab文件: ~/.config/compass-ci/include/lab/$lab.yaml
这个文件是在申请账户成功的时候写在这里的，包含了用户在这个集群里的my_token

### host文件（文件名来自testbox字段）
- 首先查找路径\$CCI_REPOS/lab-\$lab/hosts/有没有同名文件，有则加载，没有的话继续往下找
- 查找$LKP_SRC/hosts/有没有同名文件
    
如果上面两个都没有，则根据testbox得到tbox_group,例如taishan200-2280-2s64p-256g--a42的tbox_group是taishan200-2280-2s64p-256g，再次在上面两个目录查找同名文件，如果最终未找到，会报错。

 
## 3. job的本地解析
job yaml的书写和提交有很多特殊的用法，他们在提交的时候在本地会进行解析。

下面我们参考lkp-tests/jobs/README.md，学习一下job yaml的特殊写法

## 3.1 在yaml文件里加载其他的yaml文件
这里用lkp-tests/jobs/ssh-on-fail.yaml这个文件作为示例：
``` yaml
<< : jobs/ssh.yaml

on_fail:
  sleep: 6h
```
"<<"作为一个key时, value值可以是一个文件路径（路径是相对于$LKP_SRC），就会把这个文件的内容加载到当前的yaml文件中。
    
## 3.2 ERB模板调用Ruby代码
这里用lkp-tests/jobs/ssh.yaml这个文件作为示例
```
ssh_pub_key:
    <%=
     begin
       File.read("#{ENV['HOME']}/.ssh/id_rsa.pub").chomp
     rescue
       nil
     end
     %>
sshd:
sleep: 6h
```
”<%=”和 ”%>“ 两个符号以内可以写Ruby代码，代码可以做一下操作或者返回一个值
    
## 3.3 多个任务写在一个yaml文件方便一次提交
主要是使用**---**分割
```
hash_0
---
hash_1
---
...
---
hash_N
```
    
上面就会分割成一下几个job来提交
```
hash_0
hash_0 + hash_1
...
hash_0 + hash_N
```

## 3.4 matrix参数
在命令行输入多个参数时，我们为了简化输入，可以按照一定的格式输入来简化：
```
submit iperf.yaml arg1:args2:args3=1:2:3 -o ~/tmp
```

在job yaml也可以使用
``` yaml
arg1:arg2:arg3:
    - 1:2:3
    - 4:5:6
```
> “|”符号也有相同的功能， 需要注意的是“|”只能在yaml文件里使用，在命令行会被当做管道符解析而导致错误

``` yaml
arg1|arg2|arg3:
    - 1|2|3
    - 4|5|6
```
    
## 3.5 自动分解job参数
- 根据测试脚本参数分解job

    如果在测试脚本iperf($LKP_SRC/tests下的脚本)中,脚本头部出现“# - ”开头的语句，就会把后面的这个字段作为分解参数，例如这里protocol就是这个脚本的分解参数（当然在脚本中也会使用这个参数）。
    ```
    #!/bin/sh
    # - protocol
    
    ...
    ```
    
    当提交的job定义了多个protocol参数：
    ``` yaml
    iperf:
        protocol:
            - tcp
            - udp
    ```
    这时就会自动分解这个yaml文件成两个job来提交，protocol的值不同，一个job是tcp,一个是udp.(可以用submit -o DIR来测试一下)

- 根据os相关的参数分解job
    
    我们设置了一些os的一些字段，当他们的value是列表时，也会拆分成多个job提交。这些字段有: **testbox os os_arch os_version arch os_mount**
        
    下面定义的字段就会提交两个job,一个job使用openEuler20.03测试，一个使用openEuler20.09测试。
    ```
        os: openeuelr
        os_verson:
            - 20.03
            - 20.09
    ```

# 4.调度器处理job
    任务转化成json格式提交到调度器的submit_job接口，然后开始这个job的处理
## 4.1 submit_job入口： 
    接口函数位于$CCI_SRC/src/scheduler/scheduler.cr
    
    post "/submit_job" do |env|
        env.sched.submit_job.to_json
    end
    
> submit_job: $CCI_SRC/src/scheduler/submit_job.cr (废弃)
## 4.2 submit_job函数
    函数位于: $CCI_SRC/src/scheduler/auto_depend_submit_job.cr

    - job的初始化，然后做一些检查，比如必要字段检查,用户检查等。
    - @env.cluster.handle_job: $CCI_SRC/src/scheduler/plugins/cluster.cr
        处理传入的job, 返回一个job的列表，列表长度>=1
    - 设置job_id: redis中的key(queues/seqno), 每次自增1作为新job的id
    - id2secrets敏感信息处理：在redis里保存job的secrets信息, 格式{id2secrets: {job_id: $secrets}}, 同时在job中删除，避免敏感信息泄露。
    - 保存job到es数据库
    - 保存job到etcd
    - 保存job_id到etcd的指定队列中等待测试机执行： sched/ready/#{job.queue}/#{job.subqueue}/#{job.id}
    - 返回response
    
# 5. 测试机请求job
测试机用ipxe请求任务: 具体参考compass-ci/doc/install/cci-use-ipxe-to-boot.md

# 6.job测试机上的执行
测试机是通过ipxe启动以后，这个过程中除了加载系统的文件以外，还会加载其他任务需要的文件，比如job.cgz、lkp-tests的cgz包等，这些包都会在启动阶段解压到系统对应的目录上。

## 6.1 任务的入口
lkp-tests的cgz包解压以后会生成很多文件，比如下面两个文件：
- /etc/init.d/lkp-bootstrap文件（原文件为$LKP_SRC/rootfs/addon/etc/init.d/lkp-bootstrap）
- /etc/rc.local文件（原文件为$LKP_SRC/rootfs/addon/etc/rc.local）

/etc/rc.local里会设置开机启动/etc/init.d/lkp-bootstrap进程，这个进程就是测试任务的入口

## 6.2 lkp-bootstrap进程
这个进程会从/proc/cmdline里读取内核的参数，并声明成变量使用，这些参数有：user(lkp)，job(/lkp/scheduled/job.yaml)，ip(dhcp)等。

然后声明环境变量：
- export LKP_USER=$user          # 一般默认用户是lkp
- export LKP_SRC=/lkp/$user/src  # lkp-tests源码解压的目录

最后调用脚本：$LKP_SRC/bin/lkp-setup-rootfs

## 6.3 $LKP_SRC/bin/lkp-setup-rootfs的执行
- boot_init  （函数来自$LKP_SRC/lib/bootstrap.sh脚本）
    ```
    首先做一些基础的配置，然后打印“Kernel tests: Boot OK!"
    然后再做一些其他的配置，比如设置hostname,host,dns，添加lkp用户，安装cgz解压的依赖包(比如针对initramfs启动的测试机)，设置网络, 逻辑卷挂载等。
    ```

- install_proxy
    ```
    配置协议代理： 比如http代理、docker代理、yum或者apt安装代理等
    ```

- 上报tbox_state状态为running
- 不是initramfs方式启动的测试机，此时会下载依赖包并安装

- 执行 $LKP_SRC/bin/run-lkp $job
    ```
    这里的$job就是/lkp/scheduled/job.yaml
    ```

- 测试结束，reboot测试机

## 6.4 $LKP_SRC/bin/run-lkp的执行
- job-init  (函数来自$LKP_SRC/lib/job-init.sh)
    ```
    加载/lkp/scheduled/job.sh
    job.sh是在服务端生成的，和job.yaml一起压缩到job.cgz中，由测试机下载和使用。
    
    设置测试用的环境变量：
    1. 执行job.sh里面的export_top_env函数
    2. 读取/lkp/scheduled/secrets.yaml，这个提交job时的secrets下的字段，读取时给所有变量名加前缀”secrets_“。
    ```
- 上报任务的状态为running
- 执行job.sh里面的run_job函数，正式开始执行任务
- 上报任务的状态为post_run
- 执行$LKP_SRC/bin/post-run 
    ```    
    开始上传结果,上传的文件主要是$TMP（/tmp/lkp）下的一些文件.
    也可以在测试脚本里自定义上传：
        . $LKP_SRC/lib/upload.sh
        upload_files -t $dest_dir $local_dir/*
    $dest_dir是在远端result_root下创建目录，把$local_dir下的文件都上传到远端这个目录下
    ```
- 上报任务的开始时间、结束时间
- check_oom, 如果有out of memery错误，上报任务状态为”OOM“
- 正常结束的任务上报状态”finished“，或者是一下几种：
    - incomplete状态 一般是程序没有运行完，有以下可能：
        - setup、deamon脚本报错
        - 使用die()语句退出
    - failed状态一般是测试脚本出错
    
    以上两类报错的情况下，如果job yaml中定义了on_fail字段，上报完就会执行on_fail。

    - disturbed状态一般表示有用户正在登录

- job_done
    ```
    任务结束，如果有用户正在登陆，会上报manual_check状态，并等待。
    ```

# 结果查看
任务上传以后可以在result目录查看结果： 具体查看的方法可以参考：compass-ci/doc/result/browse-results.zh.md
