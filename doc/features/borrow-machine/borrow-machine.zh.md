# 前置准备

- 申请account
- 配置默认yaml文件

如果未完成以上步骤，请参考 [apply-account.md](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/account/apply-account.md) 完成操作。

# 申请测试机

## 1. 生成本地公钥

    使用下面命令查看是否已存在ssh公钥：

        ls ~/.ssh/*.pub

    如果当前没有现成的公钥，请使用下面命令进行生成：

        ssh-keygen

## 2. 选择job yaml

    在 ~/lkp-tests/jobs 目录下为您提供了众多job实例。

    使用以下命令可筛选出借用机器的实例：

        cd ~/lkp-tests/jobs
        ls borrow*

## 3. 提交job

    使用以下命令样例提交job：

    容器:

        submit -c -m testbox=dc-2g os_mount=container docker_image=centos:8 borrow-1h.yaml

    虚拟机:

        submit -c -m testbox=vm-2p8g borrow-1h.yaml

    物理机：

        submit -c -m testbox=taishan200-2280-2s48p-256g borrow-1h.yaml

    - 使用以上命令，您可以实时查看job状态，测试机正常运行后将直接登入。
    - 借用成功后，会同时发送邮件通知，提供测试机配置信息及登录命令，请注意查收。
    - 租借期内，您可以通过邮件内提供的登录命令再次登录测试机。
    - 登录命令仅对当前测试机有效，测试机归还后，登录命令将不可用。

## 4. 测试机续租

    在测试机过期前，登陆测试机进行续租。
    获取测试机租期：
        lkp-renew -g
    续租N天：
        lkp-renew Nd

## 5. 退还测试机

    手动归还（推荐使用）：

        测试机使用完成后，及时执行‘reboot’命令进行测试机归还，避免闲置造成资源浪费。

    到期自动归还：

        借用期限到达后，测试接将自动重启归还。

    - 所有测试机在执行‘reboot’命令后都会被归还，归还后不可再次登录使用。
    - 机器归还后，如果您还需要继续使用测试机，请重新提交job申请新的测试机。

# FAQ

* 自定义借用时长

    在借用机器的yaml实例文件中，找到 **runtime** 字段，根据需求修改借用时长。

	借用机器可以按照小时（h）、天（d）来计算。
	借用时长最多不超过10天。

* submit命令指导

    学习submit命令，您可以使用 以下命令查看submit命令的各项参数及使用方法：

        submit -h

    也可以参考submit命令手册学习submit命令高级用法：

    [submit命令详解](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/job/submit/submit-job.zh.md)

* 可选的testbox

    查看可选的testbox列表，请参考：https://gitee.com/wu_fengguang/lab-z9/tree/master/hosts

    >![](./../../public_sys-resources/icon-note.gif) **说明：**
    >
    > - 容  器: dc-xxx
    > - 虚拟机: vm-xxx
    > - 物理机: taishan200-2280-xxx



    >![](./../../public_sys-resources/icon-notice.gif) **注意：**
    > - 物理机的testbox若选择以`--axx`结尾的，则表示指定到了具体的某一个物理机。若此物理机任务队列中已经有任务在排队，则需要等待队列中前面的任务执行完毕后，才会轮到你提交的borrow任务。
    > - 物理机的testbox若不选择以`-axx`结尾的，表示不指定具体的某一个物理机。则此时集群中的空闲物理机会即时被分配执行你的borrow任务。

* 如何 borrow 指定的操作系统

    关于支持的`os`, `os_arch`, `os_version`，参见：[os-os_verison-os_arch.md](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/job/fields/os-os_verison-os_arch.md)
