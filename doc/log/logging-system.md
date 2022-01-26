# compass-ci日志系统

## EFK日志系统
- compass-ci对日志系统的诉求
  - 能够收集多种类型的日志，compass-ci集群有docker容器的日志、执行机的串口日志（日志文件）需要收集；
  - 能够快速聚合分散的日志进行集中管理，compass-ci集群的日志分散在多个地方：部署服务的服务器、执行任务的物理机、IBMC管理机
  - 可视化的平台，方便对日志进行分析及展示
  - 高效，集群会产生大量日志，需要系统能快速处理，不产生堆积
  - 开源组件
  结合以上诉求，compass-ci最终选择了EFK系统
- 在compass-ci中的使用
```
    docker/serial日志（生产） -> sub-fluentd（收集） -> master-fluentd（聚合） -> es(存储) -> kibana（展示）
                                                           ｜
                                        monitoring   <- rabbitmq -> serial-logging -> job's result/dmesg file
```

## 日志生产

### docker服务日志
- 配置
  启动sub-fluentd之后，docker需要做相应的配置将日志转发到sub-fluentd

  默认情况下，Docker使用json-file日志驱动程序，该驱动程序在内部缓存容器日志为JSON（docker logs日志来源）
  - 全局配置
    /etc/docker/daemon.json

    需要重启docker服务全局配置才会生效
```
{
  # 日志转发到fluentd
  "log-driver": "fluentd",
  "log-opts":{
    # fluentd服务地址
    "fluentd-address": "localhost:24225",
    # fluentd-docker异步设置,避免fluentd失去连接之后导致Docker容器异常
    "fluentd-async-connect": "true",
    # 配置转发到fluentd日志的标签为容器名，用于区分不同容器的日志
    "tag": "{{.Name}}"
  }
}
```
  - 单个docker容器配置

    全局配置后所有的docker日志都会被转发到sub-fluentd，若未做全局配置，只想特定容器进行转发，可以使用以下配置

    docker run --log-driver=fluentd --log-opt fluentd-address=fluentdhost:24225 --log-opt tag=xxx

    有些日志信息比较敏感，不想转发到fluentd，可以单独配置为默认的json-file模式

    docker run --log-driver=json-file
- 日志流程
```
  docker -> sub-fluentd -> master-fluentd -> rabbitmq -> monitoring
                                      `----> es -> kibana
```
  - es

    存储到es是为了后续在kibana上搜索展示分析
  - rabbitmq

    存储到rabbitmq中间件，为monitoring服务提供数据
  - monitoring服务

    submit -m的服务端，近实时的返回job执行过程中与服务端交互产生的日志
- 日志内容

  compass-ci的服务都是用docker的方式部署
  - 非自主开发的服务，如es：
```
wuzhende@crystal ~% docker logs -f sub-fluentd | grep es-server01
2022-01-17 05:13:42.000000000 +0800 es-server01: {"type": "server", "timestamp": "2022-01-16T21:13:42,579Z", "level": "WARN", "component": "o.e.m.j.JvmGcMonitorService", "cluster.name": "docker-cluster", "node.name": "node-1", "message": "[gc][young][152465][89] duration [1s], collections [1]/[1.1s], total [1s]/[5.8s], memory [19.4gb]->[1.9gb]/[30gb], all_pools {[young] [17.5gb]->[0b]/[0b]}{[old] [1.4gb]->[1.5gb]/[30gb]}{[survivor] [367.5mb]->[389.8mb]/[0b]}", "cluster.uuid": "FJFweh9LQ6mKes6uwHQL_g", "node.id": "keFEKD-WTBe0tHF4fbS4MA"  }
2022-01-17 05:13:42.000000000 +0800 es-server01: {"type": "server", "timestamp": "2022-01-16T21:13:42,579Z", "level": "WARN", "component": "o.e.m.j.JvmGcMonitorService", "cluster.name": "docker-cluster", "node.name": "node-1", "message": "[gc][152465] overhead, spent [1s] collecting in the last [1.1s]", "cluster.uuid": "FJFweh9LQ6mKes6uwHQL_g", "node.id": "keFEKD-WTBe0tHF4fbS4MA"  }
2022-01-17 05:23:21.000000000 +0800 es-server01: {"type": "server", "timestamp": "2022-01-16T21:23:21,413Z", "level": "WARN", "component": "o.e.m.f.FsHealthService", "cluster.name": "docker-cluster", "node.name": "node-1", "message": "health check of [/srv/es/nodes/0] took [6002ms] which is above the warn threshold of [5s]", "cluster.uuid": "FJFweh9LQ6mKes6uwHQL_g", "node.id": "keFEKD-WTBe0tHF4fbS4MA"  }
```
  - 自主开发的服务，如调度器:
```
wuzhende@crystal ~% docker logs -f sub-fluentd | grep scheduler-3000
2022-01-17 05:39:59.000000000 +0800 scheduler-3000: {"level_num":2,"level":"INFO","time":"2022-01-17T05:39:59.902+0800","from":"172.17.0.1:52468","message":"access_record","status_code":200,"method":"GET","resource":"/boot.ipxe/mac/44-67-47-e9-79-c0","testbox":"sched-crystal-44-67-47-e9-79-c0","api":"boot","elapsed_time":1801792.188619,"elapsed":"1801792.19ms"}
2022-01-17 05:40:10.000000000 +0800 scheduler-3000: {"level_num":2,"level":"INFO","time":"2022-01-17T05:40:10.925+0800","from":"172.17.0.1:37110","message":"access_record","status_code":200,"method":"GET","resource":"/boot.ipxe/mac/84-46-fe-73-b2-39","testbox":"taishan200-2280-2s64p-256g--a1004","api":"boot","elapsed_time":1804795.552323,"elapsed":"1804795.55ms"}
2022-01-17 05:40:23.000000000 +0800 scheduler-3000: {"level_num":2,"level":"INFO","time":"2022-01-17T05:40:23.450+0800","from":"172.17.0.1:40006","message":"access_record","status_code":200,"method":"GET","resource":"/boot.ipxe/mac/44-67-47-85-d5-48","testbox":"taishan200-2280-2s48p-256g--a1008","api":"boot","elapsed_time":1803608.442844,"elapsed":"1803608.44ms"}
```
- 日志级别

  compass-ci的服务使用ruby或者crystal语言开发，两者之间对日志等级的定义不相同

  我们以crystal的日志级别为准，对ruby重新进行定义

  代码：$CCI_SRC/lib/json_logger.rb
```
class JSONLogger < Logger
  LEVEL_INFO = {
    'TRACE' => 0,
    'DEBUG' => 1,
    'INFO' => 2,
    'NOTICE' => 3,
    'WARN' => 4,
    'ERROR' => 5,
    'FATAL' => 6
  }.freeze
```
- 日志格式
```
  json类型：{
  # 日志级别
  "level_num":2,
  # 日志级别
  "level":"INFO",
  # 日志产生的时间
  "time":"2022-01-17T05:40:10.925+0800",
  # 请求来源
  "from":"172.17.0.1:37110",
  # 日志内容
  "message":"access_record",
  # http状态码
  "status_code":200,
  # 请求类型
  "method":"GET",
  # 请求地址
  "resource":"/boot.ipxe/mac/84-46-fe-73-b2-39",
  # 执行机名
  "testbox":"taishan200-2280-2s64p-256g--a1004",
  # 相关的任务id
  "job_id": crystal1344467
  # 接口耗时，ms
  "elapsed_time":1804795.552323,
  # 接口耗时，不带单位
  "elapsed":"1804795.55ms"
}
```
  代码：$CCI_SRC/src/lib/json_logger.cr
```
  private def get_env_info(env : HTTP::Server::Context)
    @env_info["status_code"] = env.response.status_code
    @env_info["method"] = env.request.method
    @env_info["resource"] = env.request.resource

    @env_info["testbox"] = env.get?("testbox").to_s if env.get?("testbox")
    @env_info["job_id"] = env.get?("job_id").to_s if env.get?("job_id")
    @env_info["job_state"] = env.get?("job_state").to_s if env.get?("job_state")
    @env_info["api"] = env.get?("api").to_s if env.get?("api")

    set_elapsed(env)
    merge_env_log(env)
  end
```

## 执行机串口日志
执行机执行任务时，会将串口以及一些关键日志保存到指定目录下：/srv/cci/serial/logs/$hostname

不同类型的执行机有不同的实现方式：
- 物理机

  通过部署conserver容器到ibmc管理机上

  该容器会将集群物理机的串口日志重定向到ibmc管理机的指定目录
- qemu

  启动qemu时，将日志进行重定向

  关键代码: $CCI_SRC/providers/kvm.sh
```
run_qemu()
{
        #append=(
        #       rd.break=pre-mount
        #       rd.debug=true
        #)
        if [ "$DEBUG" == "true" ];then
                "${kvm[@]}" "${arch_option[@]}" --append "${append}"
        else
                # The default value of serial in QEMU is stdio.
                # We use >> and 2>&1 to record serial, stdout, and stderr together to log_file
                "${kvm[@]}" "${arch_option[@]}" --append "${append}" >> $log_file 2>&1
		run kernel/os once > one-dmesg-file >> upload to job's result dir
		data process, check 2 side match, warn email
        fi

        local return_code=$?
        [ $return_code -eq 0 ] || echo "[ERROR] qemu start return code is: $return_code" >> $log_file
}
```
  - docker

  启动容器时，将docker日志重定向

  关键代码：$CCI_SRC/providers/docker/run.sh
```
cmd=(
        docker run
        --rm
        --name ${job_id}
        --hostname $host.compass-ci.net
        --cpus $nr_cpu
        -m $memory
        --tmpfs /tmp:rw,exec,nosuid,nodev
        -e CCI_SRC=/c/compass-ci
        -v ${load_path}/lkp:/lkp
        -v ${load_path}/opt:/opt
        -v ${DIR}/bin:/root/sbin:ro
        -v $CCI_SRC:/c/compass-ci:ro
        -v /srv/git:/srv/git:ro
        -v /srv/result:/srv/result:ro
        -v /etc/localtime:/etc/localtime:ro
        -v ${busybox_path}:/usr/local/bin/busybox
        --log-driver json-file
        --log-opt max-size=10m
        --oom-score-adj="-1000"
        ${docker_image}
        /root/sbin/entrypoint.sh
)

"${cmd[@]}" 2>&1 | tee -a "$log_dir"
```

- 串口日志流程

  日志文件：/srv/cci/serial/logs/$hostname -> sub-fluentd -> master-fluentd -> rabbitmq -> serial-logging -> result/dmesg


## 日志收集聚合-fluentd
  在我们的系统中分为sub-fluentd和master-fluentd两种服务
- fluentd-base
  sub-fluentd和master-fluentd依赖的基础镜像,直接构建即可
```
  cd $CCI_SRC/container/fluentd-base
  ./build
```
- sub-fluentd
  - 作用

    收集所在机器上的docker日志以及串口日志，并转发到master-fluentd上
  - 位置

    部署到需要收集日志的机器上
  - 部署
```
    cd $CCI_SRC/container/sub-fluentd
    ./build
    ./start
```

    用docker容器的方式部署到机器上
  - 配置文件

    配置文件$CCI_SRC/container/sub-fluentd/docker-fluentd.conf
  - 关键配置解读

```
<worker 0>
<source>
  @type tail
  path /srv/cci/serial/logs/*
  pos_file /srv/cci/serial/fluentd-pos/serial.log.pos
  tag serial.*
  path_key serial_path
  refresh_interval 1s
  <parse>
    @type none
  </parse>
</source>
```

  配置tail输入插件，允许fluentd从文本文件的尾部读取事件，它的行为类似于tail -F命令

  监听/srv/cci/serial/logs/目录下的所有文本文件，所以我们只需要把串口日志存到该目录下，就会被自动收集

```
<source>
  @type forward
  bind 0.0.0.0
</source>
```

  配置forward输入插件侦听 TCP 套接字以接收事件流，接收网络上转发过来的日志

  可以用来收集docker服务的日志，需要docker服务也做相应配置，将日志转发到sub-fluentd

```
<store>
  @type forward
  flush_interval 0
  send_timeout 60
  heartbeat_interval 1
  recover_wait 10
  hard_timeout 60
  <server>
    master-fluentd
    host "#{ENV['MASTER_FLUENTD_HOST']}"
    port "#{ENV['MASTER_FLUENTD_PORT']}"
  </server>
</store>
```

  配置forward输出插件将日志转发到master-fluentd节点，达到日志聚合的目的

- master-fluentd
  - 作用

    接收集群里的sub-fluentd转发过来的日志，再将日志保存到es/rabbitmq里
  - 位置

    部署到主服务器上
  - 部署

```
    cd $CCI_SRC/container/master-fluentd
    ./build
    ./start
```

    用docker容器的方式部署到服务器上
  - 配置文件
    $CCI_SRC/container/master-fluentd/docker-fluentd.conf
  - 关键配置解读

```
<source>
  @type forward
  bind 0.0.0.0
</source>
```

配置forward输入插件侦听 TCP 套接字以接收事件流，接收sub-fluentd转发过来的日志

```
<filter **>
  @type record_transformer
  enable_ruby
  <record>
    time ${time.strftime('%Y-%m-%dT%H:%M:%S.%3N+0800')}
  </record>
</filter>
```

往json格式的日志中加入time字段

```
<match serial.**>
  @type rabbitmq
  host 172.17.0.1
  exchange serial-logging
  exchange_type fanout
  exchange_durable false
  heartbeat 10
  <format>
    @type json
  </format>
</match>
```

将收到的串口日志转发到rabbitmq中

```
<filter **>
  @type parser
  format json
  emit_invalid_record_to_error false
  key_name log
  reserve_data true
</filter>
```

将json日志中的log字段展开

原始日志:

```
{
    "container_id": "227c5ed4f008c84c345c18762c9aeae41207162f87df627b3b6e430f1bebe690",
    "container_name": "/s001-alpine-3005",
    "source": "stdout",
    "log": "{\"level_num\":2,\"level\":\"INFO\",\"time\":\"2021-12-16T10:08:00.350+0800\",\"from\":\"172.17.0.1:59526\",\"message\":\"access_record\",\"status_code\":101,\"method\":\"GET\",\"resource\":\"/ws/boot.ipxe/mac/0a-03-4b-56-32-3d\",\"testbox\":\"vm-2p4g.taishan200-2280-2s64p-256g--a45-3\"}",
}
```

展开后：

```
{
    "container_id": "227c5ed4f008c84c345c18762c9aeae41207162f87df627b3b6e430f1bebe690",
    "container_name": "/s001-alpine-3005",
    "source": "stdout",
    "log": "{\"level_num\":2,\"level\":\"INFO\",\"time\":\"2021-12-16T10:08:00.350+0800\",\"from\":\"172.17.0.1:59526\",\"message\":\"access_record\",\"status_code\":101,\"
method\":\"GET\",\"resource\":\"/ws/boot.ipxe/mac/0a-03-4b-56-32-3d\",\"testbox\":\"vm-2p4g.taishan200-2280-2s64p-256g--a45-3\"}",
    "time": "2021-12-16T10:08:00.000+0800",
    "level_num": 2,
    "level": "INFO",
    "from": "172.17.0.1:59526",
    "message": "access_record",
    "status_code": 101,
    "method": "GET",
    "resource": "/ws/boot.ipxe/mac/0a-03-4b-56-32-3d",
    "testbox": "vm-2p4g.taishan200-2280-2s64p-256g--a45-3"
}
```

这样做的好处是：es会为展开后的字段设置索引，方便后续对日志的搜索分析

```
<match **>
  @type copy

  <store>
    @type elasticsearch
    host "#{ENV['LOGGING_ES_HOST']}"
    port "#{ENV['LOGGING_ES_PORT']}"
    user "#{ENV['LOGGING_ES_USER']}"
    password "#{ENV['LOGGING_ES_PASSWORD']}"
    suppress_type_name true
    flush_interval 1s
    num_threads 10
    index_name ${tag}
    ssl_verify false
    log_es_400_reason true
    with_transporter_log true
    reconnect_on_error true
    reload_on_failure true
    reload_connections false
    template_overwrite
    template_name logging
    template_file /fluentd/mapping-template
  </store>

  <store>
    @type rabbitmq
    host 172.17.0.1
    exchange docker-logging
    exchange_type fanout
    exchange_durable false
    heartbeat 10
    <format>
      @type json
      @type json
    </format>
  </store>
</match>
```

将docker容器的日志转发存储到es和redis中

## 日志处理

### monitoring服务
- 需求

  使用submit提交任务时，想要知道job执行到了哪个阶段，希望能把job执行过程的日志打印出来
- 数据来源

  master-fluentd转存到rabbitmq的docker日志
- 功能

  近实时的返回满足条件的日志，无法回溯
- api

  ws://$ip:20001/filter
- 客户端如何使用

  submit提交任务时添加'-m'选项：
```
hi8109@account-vm ~% submit -m borrow-1d.yaml testbox=dc-8g
submit_id=65356462-2547-4c64-af3c-e58cc32fb473
submit /home/hi8109/lkp-tests/jobs/borrow-1d.yaml, got job id=z9.13283216
query=>{"job_id":["z9.13283216"]}
connect to ws://172.168.131.2:20001/filter
{"level_num":2,"level":"INFO","time":"2022-01-06T16:18:45.164+0800","job_id":"z9.13283216","message":"","job_state":"submit","
8g/centos-7-aarch64/86400/z9.13283216","status_code":200,"method":"POST","resource":"/submit_job","api":"submit_job","elapsed_
{"level_num":2,"level":"INFO","time":"2022-01-06T16:18:45.262+0800","job_id":"z9.13283216","result_root":"/srv/result/borrow/2
216","job_state":"set result root","status_code":101,"method":"GET","resource":"/ws/boot.container/hostname/dc-8g.taishan200-2
200-2280-2s48p-256g--a70-9"}
{"level_num":2,"level":"INFO","time":"2022-01-06T16:18:45.467+0800","from":"172.17.0.1:53232","message":"access_record","statu
.container/hostname/dc-8g.taishan200-2280-2s48p-256g--a70-9","testbox":"dc-8g.taishan200-2280-2s48p-256g--a70-9","job_id":"z9.
{"level_num":2,"level":"INFO","time":"2022-01-06T16:18:47.477+0800","from":"172.17.0.1:44714","message":"access_record","statu
trd_tmpfs/z9.13283216/job.cgz","job_id":"z9.13283216","job_state":"download","api":"job_initrd_tmpfs","elapsed_time":0.581944,

The dc-8g testbox is starting. Please wait about 30 seconds
{"level_num":2,"level":"INFO","time":"2022-01-06T16:18:52+0800","mac":"02-42-ac-11-00-03","ip":"","job_id":"z9.13283216","stat
s48p-256g--a70-9","status_code":200,"method":"GET","resource":"/~lkp/cgi-bin/lkp-wtmp?tbox_name=dc-8g.taishan200-2280-2s48p-25
-03&ip=&job_id=z9.13283216","api":"lkp-wtmp","elapsed_time":75.77575,"elapsed":"75.78ms"}
{"level_num":2,"level":"INFO","time":"2022-01-06T16:19:47.968+0800","from":"172.17.0.1:38220","message":"access_record","statu
i-bin/lkp-jobfile-append-var?job_file=/lkp/scheduled/job.yaml&job_id=z9.13283216&job_state=running","job_id":"z9.13283216","ap
.933762,"elapsed":"5447.93ms","job_state":"running","job_stage":"running"}
```

### serial-logging服务
- 功能

  在job的结果目录下生成dmesg文件
- 数据来源

  master-fluentd转存到rabbitmq的串口日志
- 代码

  $CCI_SRC/src/monitoring/parse_serial_logs.cr
- 示例:
```
wuzhende@z9 /srv/result/build-pkg/2022-01-19/dc-16g/openeuler-20.03-pre-aarch64/pkgbuild-aur-j-java-testng-a6f1c79551cf6e/z9.13368603% ll
total 1.1M
-rw-r--r-- 1 lkp  lkp 3.4K 2022-01-19 23:59 job.yaml
-rwxrwxr-x 1 lkp  lkp 4.1K 2022-01-19 23:59 job.sh
-rw-rw-r-- 1 lkp  lkp 1.4K 2022-01-20 00:00 time-debug
-rw-rw-r-- 1 lkp  lkp  860 2022-01-20 00:00 stdout
-rw-rw-r-- 1 lkp  lkp  373 2022-01-20 00:00 stderr
-rw-rw-r-- 1 lkp  lkp   33 2022-01-20 00:00 program_list
-rw-rw-r-- 1 lkp  lkp 1.4K 2022-01-20 00:00 output
-rw-rw-r-- 1 lkp  lkp 3.3K 2022-01-20 00:00 meminfo.gz
-rw-rw-r-- 1 lkp  lkp   43 2022-01-20 00:00 last_state
-rw-rw-r-- 1 lkp  lkp  634 2022-01-20 00:00 heartbeat
-rw-rw-r-- 1 lkp  lkp  218 2022-01-20 00:00 build-pkg
-rw-rw-r-- 1 lkp  lkp   24 2022-01-20 00:00 boot-time
-rw-rw-r-- 1 root lkp  481 2022-01-20 00:00 stderr.json
-rw-rw-r-- 1 root lkp 2.7K 2022-01-20 00:00 meminfo.json.gz
-rw-rw-r-- 1 root lkp 3.7K 2022-01-20 00:00 dmesg
-rw-rw-r-- 1 root lkp   97 2022-01-20 00:00 last_state.json
-rw-rw-r-- 1 root lkp 1.5K 2022-01-20 00:00 stats.json
wuzhende@z9 /srv/result/build-pkg/2022-01-19/dc-16g/openeuler-20.03-pre-aarch64/pkgbuild-aur-j-java-testng-a6f1c79551cf6e/z9.13368603% cat dmesg
2022-01-19 23:59:56 starting DOCKER
http://172.168.131.2:3000/job_initrd_tmpfs/z9.13368603/job.cgz
http://172.168.131.2:8800/upload-files/lkp-tests/aarch64/v2021.09.23.cgz
http://172.168.131.2:8800/upload-files/lkp-tests/e9/e94df9bd6a2a9143ebffde853c79ed18.cgz
2022-01-20 00:00:00 [INFO] -- Kernel tests: Boot OK!
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100  2130  100  2130    0     0  2080k      0 --:--:-- --:--:-- --:--:-- 2080k
System has not been booted with systemd as init system (PID 1). Can't operate.
Failed to connect to bus: Host is down
System has not been booted with systemd as init system (PID 1). Can't operate.
Failed to connect to bus: Host is down
/usr/bin/wget -q --timeout=1800 --tries=1 --local-encoding=UTF-8 http://172.168.131.2:3000/~lkp/cgi-bin/lkp-wtmp?tbox_name=dc-16g.taishan200-2280-2s48p-256g--a103-0&tbox_state=running&mac=02-42-ac-11-00-09&ip=172.17.0.9&job_id=z9.13368603 -O /dev/null
download http://172.168.131.2:8800/initrd/pkg/container/openeuler/aarch64/20.03-pre/build-pkg/4.3.90-1.cgz
/usr/bin/wget -q --timeout=1800 --tries=1 --local-encoding=UTF-8 http://172.168.131.2:8800/initrd/pkg/container/openeuler/aarch64/20.03-pre/build-pkg/4.3.90-1.cgz -O /tmp/tmp.cgz
3193 blocks
/lkp/lkp/src/bin/run-lkp
RESULT_ROOT=/result/build-pkg/2022-01-19/dc-16g/openeuler-20.03-pre-aarch64/pkgbuild-aur-j-java-testng-a6f1c79551cf6e/z9.13368603
job=/lkp/scheduled/job.yaml
result_service: raw_upload, RESULT_MNT: /172.168.131.2/result, RESULT_ROOT: /172.168.131.2/result/build-pkg/2022-01-19/dc-16g/openeuler-20.03-pre-aarch64/pkgbuild-aur-j-java-testng-a6f1c79551cf6e/z9.13368603, TMP_RESULT_ROOT: /tmp/lkp/result
run-job /lkp/scheduled/job.yaml
/usr/bin/wget -q --timeout=1800 --tries=1 --local-encoding=UTF-8 http://172.168.131.2:3000/~lkp/cgi-bin/lkp-jobfile-append-var?job_file=/lkp/scheduled/job.yaml&job_id=z9.13368603&job_state=running -O /dev/null
which: no time in (/root/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/lkp/lkp/src/bin:/lkp/lkp/src/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/lkp/lkp/src/bin:/lkp/lkp/src/sbin)
==> Making package: java-testng 7.4.0-1 (Thu Jan 20 00:00:04 CST 2022)
==> Checking runtime dependencies...
==> Checking buildtime dependencies...
==> Retrieving sources...
  -> Downloading java-testng-7.4.0.tar.gz...
curl: (7) Failed to connect to github.com port 443: Connection timed out
==> ERROR: Failure while downloading java-testng-7.4.0.tar.gz
    Aborting...
/usr/bin/wget -q --timeout=1800 --tries=1 --local-encoding=UTF-8 http://172.168.131.2:3000/~lkp/cgi-bin/lkp-jobfile-append-var?job_file=/lkp/scheduled/job.yaml&job_id=z9.13368603&job_state=post_run -O /dev/null
kill 142 vmstat --timestamp -n 10
wait for background processes: 144 meminfo
/usr/bin/wget -q --timeout=1800 --tries=1 --local-encoding=UTF-8 http://172.168.131.2:3000/~lkp/cgi-bin/lkp-jobfile-append-var?job_file=/lkp/scheduled/job.yaml&job_id=z9.13368603&loadavg=1.87%201.87%201.66%202/2191%20477&start_time=1642608003&end_time=1642608036&& -O /dev/null
/usr/bin/wget -q --timeout=1800 --tries=1 --local-encoding=UTF-8 http://172.168.131.2:3000/~lkp/cgi-bin/lkp-jobfile-append-var?job_file=/lkp/scheduled/job.yaml&job_id=z9.13368603&job_state=failed -O /dev/null
/lkp/scheduled/job.sh: line 133: /lkp/scheduled/job.yaml: Permission denied
/usr/bin/wget -q --timeout=1800 --tries=1 --local-encoding=UTF-8 http://172.168.131.2:3000/~lkp/cgi-bin/lkp-post-run?job_file=/lkp/scheduled/job.yaml&job_id=z9.13368603 -O /dev/null
LKP: exiting

Total DOCKER duration:  0.82 minutes
```
