这篇文档将告诉你如何登录测试环境去调测任务

# 1. 前提条件：
## 请先学习:
* [配置个人邮箱](https://gitee.com/openeuler/compass-ci/blob/master/doc/user-guide/apply-account.md)
* [如何申请测试机](https://gitee.com/openeuler/compass-ci/blob/master/doc/user-guide/borrow-machine.zh.md)
* [submit命令详解](https://gitee.com/openeuler/compass-ci/blob/master/doc/job/submit/submit-job.zh.md)

# 2. 操作方法

## 2.1 定义免密登录的yaml

### 方法一：在测试机运行脚本之前进入测试机调测任务

在job.yaml里加上sshd和sleep字段，测试机在运行脚本之前sleep, 并免密登录进去，手动输入命令或脚本进行调试，以spinlock.yaml为例：

```yaml
    suite: spinlock
    category: benchmark

    nr_threads:
    - 1

    sshd:
    # sleep at the bottom
    sleep: 1h
    spinlock:
```

### 方法二：在测试任务运行失败时进入测试机调测任务

在job.yaml里加上on_fail字段，并在on_fail下加上sshd和sleep字段，测试任务失败后，免密登录进去手动调试，以spinlock.yaml为例：

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

## 2.2 提交job.yaml

### 方法一：直接提交

    submit spinlock.yaml

在收到邮件后，按照邮件提示手动免密登录到执行机调测

    ssh root@api.compass-ci.openeuler.org -p $port

### 方法二：带参数提交

    submit -m -c spinlock.yaml

该方法不用查看邮件，可自动免密登录到测试机
