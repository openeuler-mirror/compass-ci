这篇文档将告诉你如何登陆测试环境

# 1. 前提条件
请先学习:
* [apply-account.md](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/apply-account.md), 配置个人邮箱
* [如何申请测试机.md](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/如何申请测试机.md), 并在本地生成RSA公私钥对
* [submit命令详解.md](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/submit命令详解.md), submit 命令详解

# 2. 操作方法
## 2.1 在job.yaml里加上sshd和sleep字段, 以host-info.yaml任务为例：

```shell
    suite: host-info
    category: functional
    pub_key: <%=
        begin
          File.read("#{ENV['HOME']}/.ssh/id_rsa.pub").chomp
        rescue
          nil
        end
        %>
    sshd:
    # sleep at the bottom
    sleep: 1h

    host-info:
```

## 2.2 以下有2种方式可以登录到测试机：
### 第一种：使用submit -m -c的方式：
    这种方式提交的任务会在指定的位置sleep并直接登陆到测试机中，适用于登陆测试环境后手动调试
    命令：submit -m -c host-info.yaml
    任务提交完成后，当测试执行到sshd后会自动登陆到测试机器上：
    效果如下：

```shell
    hi6325@account-vm ~% submit -m -c atomic.yaml
    submit atomic.yaml, got job_id=crystal.146528
    query=>{"job_id":["crystal.146528"]}
    connect to ws://localhost:11310/filter
    {"job_id": "crystal.146528", "result_root": "/srv/result/atomic/2020-12-01/vm-2p8g/openeuler-20.03-aarch64/1-1000/crystal.146528", "job_state": "set result root"
    {"job_id": "crystal.146528", "job_state": "boot"}
    {"job_id": "crystal.146528", "job_state": "download"}
    "time":"2020-12-01 10:12:33","mac":"0a-2d-7b-d9-f8-b1","ip":"172.18.252.12","job_id":"crystal.146528","state":"running","testbox":"vm-2p8g.zhyl-453231"}
    {"job_state":"running","job_id":"crystal.146528"}
    {"job_id": "crystal.146528", "state": "set ssh port", "ssh_port": "51750", "tbox_name": "vm-2p8g.zhyl-453231"}

    root@vm-2p8g ~#
```

### 第二种：根据邮件信息使用ssh方式登录测试机：
    这种是使用submit方式提交的任务完成后，系统自动发送一封邮件提醒您可以在指定时间内登陆到测试环境
    命令： submit host-info.yaml
    任务执行完成后，系统发送邮件内容如下：

```shell
    Subject: [NOTIFY Compass-ci] vm-2p8g-294828 ready to use

    Dear $my_username:
        Thanks for your participation in software ecosystem!
        According to your application, vm-2p8g-294828 has been provisioned.
        The datails are as follows:

        Login:
                ssh root@api.compass-ci.openeuler.org -p $port
                Due time:
                $deadline
        HW:
                nr_cpu: $nr_cpu
                memory: $memory
                testbox: $testbox
        OS:
	        $os $os_version $os_arch
    Regards
    Compass-Ci
```

    可通过ssh方式登陆到测试环境：
    命令： ssh root@api.compass-ci.openeuler.org -p $port
    效果如下：

```shell
    hi6325@account-vm ~% ssh root@api.compass-ci.openeuler.org -p 51400

    root@vm-2p8g ~#
```
