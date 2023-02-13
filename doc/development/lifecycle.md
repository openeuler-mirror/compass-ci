# lifecycle

管理job和testbox的生命周期

自动关闭异常的job

将异常的testbox加入重启队列

## job

### job_stage

```
                         +-----------------renew----------------------+
                         |          |                    |            |
                         |          |                    |            v
submit -> boot ----> running ->  post_run  ---> (manual_check) -> finished
            |         |             |                    |            ^
            |         |             |                    |            |
            |         |             |                    |            |
            +---------+--发生异常，lifecycle结束job-------------------+
```

job_stage详解：

- submit：提交job

  client：用户客户端或服务器内的submit

  调度器端口：/submit_job

- boot: 执行机从调度器取走任务

  client：执行机

  调度器接口： /boot.:boot_type

- running： 执行机运行lkp-tests框架代码

  client：执行机lkp-tests(set_job_state 'running')

  调度器接口： /~lkp/cgi-bin/lkp-jobfile-append-var

- post_run：执行机即将上传结果文件

  client：执行机lkp-tests(set_job_state 'post_run')

  调度器接口： /~lkp/cgi-bin/lkp-jobfile-append-var

- manual_check：执行机上有用户登陆，暂时挂起不退出

  client：执行机运行lkp-tests([ "$i" = 1 ] && set_job_state 'manual_check')

  调度器接口: /~lkp/cgi-bin/lkp-jobfile-append-var

- finished: 任务执行结束

  client：执行机/lifecycle

  调度器接口： /~lkp/cgi-bin/lkp-post-run

- renew：延长执行机的使用时间

  client：用户在执行机内执行lkp-renew命令

  调度器接口：/scheduler/renew_deadline

### job_health

job运行的结果，每个job执行之后它的job_stage最终都会是finished，但是会有不同的结果
- success: 成功运行
- lkp主动上报的错误：如OOM，incomplete，failed，load_disk_fail....
- timeout: lifecycle监测到job在某个阶段超时并将其关闭
- crash: lifecycle监测到job在某个阶段crash并将其关闭
- abnomar: 未知错误,表示某台执行机的某个任务尚未被标记为finished状态，这台执行机就开始请求新的任务

### job_fail_stage

记录当job_health出问题时所处的job_stage

### job_state

同时表示job执行到哪个阶段和job的执行结果

逐渐弃用，用job_stage和job_health取代

## testbox

```
requesting  -> booting -> running -> rebooting
               |          |           |
               +----------+-----------+-------crash/timeout-----> rebooting_queue
```

state：

- requesting：

  执行机访问调度器接口请求任务，但是还没有取走任务

  调度器接口：/boot.:boot_type

- booting：

  执行机访问调度器接口请求任务，并成功取走任务

  调度器接口：/scheduler/boot.:boot_type

- running：

  执行机已成功启动，执行lkp-tests代码上报状态

  调度器接口：/scheduler/~lkp/cgi-bin/lkp-wtmp

- rebooting：

  执行机上报，即将重启执行机

  /scheduler/~lkp/cgi-bin/lkp-wtmp

- rebooting_queue:

  lifecycle监测到执行机异常后，将执行机信息加入到重启队列中，重启服务会对执行机进行重启操作

## lifecycle处理逻辑

### deadline

job的每个阶段都设置一个超时时间

规则：
```
$CCI_SRC/src/lib/job.cr:

def get_deadline(stage, timeout=0)
    return format_add_time(timeout) unless timeout == 0

    case stage
    when "boot"
      # 3600s
      time = get_boot_time
    when "running"
      time = (self["timeout"]? || self["runtime"]? || 3600).to_s.to_i32
      extra_time = 0 if self["timeout"]?
      extra_time ||= [time / 8, 300].max.to_i32 + Math.sqrt(time).to_i32
    when "renew"
      # renew的实际时间
      return @hash["renew_deadline"]?
    when "post_run"
      time = 1800
    when "manual_check"
      time = 36000
    when "finish"
      # 物理机1200s
      # 其他60s
      time = get_reboot_time
    else
      return nil
    end

    extra_time ||= 0
    format_add_time(time + extra_time)
  end
```

### lifecycle数据结构

$CCI_SRC/src/lib/lifecycle.cr

```
def initialize
  @mq = MQClient.instance
  @es = Elasticsearch::Client.new
  @scheduler_api = SchedulerAPI.new
  @log = JSONLogger.new
  @jobs = Hash(String, JSON::Any).new
  @machines = Hash(String, JSON::Any).new
  @match = Hash(String, Set(String)).new {|h, k| h[k] = Set(String).new}
end
```

- @jobs:

Hash，存储job事件

初始化：init_from_es

从es中搜索出正在运行中的jobs，放入内存中

```
def get_active_jobs
  query = {
    "size" => 10000,
    "_source" => JOB_KEYWORDS,
    "query" => {
      "bool" => {
        "must_not" => [
          {
            "terms" => {
              "job_stage" => ["submit", "finish"]
            }
          }
        ],
        "must" => [
          {
            "exists" => {
              "field" => "job_stage"
            }
          }
        ]
      }
    }
  }
  @es.search("jobs", query)
end
```

例子:

```
@jobs = {
          "test.1": {"deadline":"2022-03-25T10:56:48+0800","time":"2022-03-25T9:00:00+0800",job_stage": "booting", "testbox": "vm-2p8g-1234"},
          "test.2": {"deadline":"2022-03-26T10:56:48+0800", "time":"2022-03-25T9:00:00+0800","job_stage": "running", "testbox": "dc-8g-1234"}
}
```

- @machines:

Hash,存储testbox的信息

初始化：init_from_es

从es中搜索出正在执行任务的testbox，放入内存中

```
def get_active_machines
  query = {
    "size" => 10000,
    "_source" => TESTBOX_KEYWORDS,
    "query" => {
      "terms" => {
        "state" => ["booting", "running", "rebooting"]
      }
    }
  }
  @es.search("testbox", query)
end
```

例子:

```
@machine = {
             "vm-2p8g-1234": {"deadline":"2022-03-25T10:56:48+0800", "time":"2022-03-25T9:00:00+0800","job_id": "test.1"},
	     "dc-8g-1234": {"deadline":"2022-03-26T10:56:48+0800", "time":"2022-03-25T9:00:00+0800","job_id": "test.2"}
}
```

- @match:

Hash, 存储执行机的job_id

例子:

```
@match = {
            "dc-8g-1234": {"test.2", "test.3"},
            "vm-2p8g-1234": {"test.1"}
}
```

### 处理流程

当job_stage发生变化时，都会调用调度器的接口来上报job的最新状态

所以我们通过调度器来向lifecycle同步job事件

```
执行机上报最新的job_stage
-> 调度器收到请求,更新数据库
-> 发送job事件到rabbitmq
-> lifecycle从rabbitmq获取job事件
-> 舍弃过期事件/处理事件
```

过期事件：事件的time小于@jobs中对应job的time

lifecycle根据job事件的job_stage值，触发相应的处理方法

```
case event["job_stage"]?
when "boot"
  on_boot_job(event)
when "finish"
  on_finish_job(event)
when "unknow"
  on_unknow_job(event)
else
  on_other_job(event)
end
```

- on_boot_job:

1. update @jobs

2. update @machines

3. deal abnormal job

```
@machines记录了一台执行机的信息：{"dc-8g-1234": {"deadline": "", "job_id": "test.1","time":"2022-03-25T8:00:00+0800",}}
-> 接收到这台执行机的最新事件：{"testbox":"dc-8g-1234","deadline": "", "job_id": "", "job_stage": "boot","time":"2022-03-25T9:00:00+0800"}}
-> 查询es数据库，发现test.1的job_stage不是finished
-> 请求调度器接口，关闭test.1这个job，并将其job_health设置为abnormal
```

- on_finish_job

1. delete @jobs[$job_id]

2. update @machines: 更新该testbox的deadline

- on_unknow_job:

处理crash的job

```
serial-logging服务监控到某台执行机crash
-> 发送job的crash事件到rabbitmq: {"job_id":"", "testbox":"", "job_stage":"unknow", "job_health": "crash","time":"2022-03-25T9:00:00+0800"}
-> lifecycle获取到crash事件
-> 关闭job，job_health设置为crash
-> 将testbox放入重启队列
-> 重启服务获取到testbox信息，重启该testbox
```

- on_other_job:

1. update @jobs

2. update @machines

### 重启服务

启动multi-qemu或multi-docker时，会同时启动一个线程去监控重启队列

```
def multiqemu
  reboot_thr = Thread.new do
    loop_reboot_testbox(HOSTNAME, 'vm', MQ_HOST, MQ_PORT)
  end
```

流程：

```
线程监控重启队列，如：taishan200-2280-2s64p-128g--a46.vm-2p8g
-> 获取需要重启的testbox信息：{"testbox": "taishan200-2280-2s64p-128g--a46.vm-2p8g", "time": "", "job_id": "$job_id"}
-> 强制退出正在运行的机器
def reboot(type, job_id)
  r, io = IO.pipe
  if type == 'dc'
    res = system("docker rm -f #{job_id}", out: io, err: io)
  else
    res = system("pkill #{job_id}", out: io, err: io)
  end
  io.close

  msg = []
  r.each_line { |l| msg << l.chomp }
  return res, msg.join(';')
end
-> 向调度器上报重启机器事件，调度器接口:/report_event
-> 调度器打印日志记录机器重启事件
```

### 处理超时的job和testbox

$CCI_SRC/src/lifecycle.cr:

```
  # 监控job事件
  lifecycle.mq_event_loop

  # 启动一个新线程去处理超时的job
  spawn lifecycle.timeout_job_loop

  # 启动一个新线程去处理超时的testbox
  spawn lifecycle.timeout_machine_loop
```

lifecycle启动时会创建两个线程分别处理超时的job和testbox

### 处理超时的job

流程：

```
loop
  -> 遍历@jobs
     -> 获取超时的任务
       -> 如果某个job的deadline时间小于当前时间，则为超时job
     -> 调用调度器接口关闭超时的job，将job_health设置为timeout
  -> sleep 30
end
```

代码：

```
def timeout_job_loop
  dead_job_id = nil
  loop do
    dead_job_id = get_timeout_job
    if dead_job_id
      close_timeout_job(dead_job_id)
      next
    end

    sleep 30
  rescue e
    @log.warn({
      "resource" => "timeout_job_loop",
      "message" => e.inspect_with_backtrace,
      "job_id" => dead_job_id
    }.to_json)
  end
end
```

例子：

```
@jobs = {
          "test.1": {"deadline":"2022-03-25T10:56:48+0800","time":"2022-03-25T9:00:00+0800",job_stage": "booting", "testbox": "vm-2p8g-1234"},
          "test.2": {"deadline":"2022-03-26T10:56:48+0800", "time":"2022-03-25T9:00:00+0800","job_stage": "running", "testbox": "dc-8g-1234"}
}
假设当前时间t="2022-03-25T12:00:00+0800"
遍历@jobs
  test.1的deadline为"2022-03-25T10:56:48+0800"，deadline < t，test.1为超时任务
  test.2的deadline为"2022-03-26T10:56:48+0800"，deadline > t，test.2未超时
```
