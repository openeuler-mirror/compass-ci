# Multi-device Test

在进行需要多台机器的测试的时候, 需要搭建多台机器的环境.

## When to using multi-device

  * 当被测试程序需要启动一个守护进程时
  * 当执行测试时需要访问另外的机器时

## How to run a multi-device test

在要提交的job.yaml中, 需要一个**cluster**字段, 它的值是一个多机环境的配
置文件的文件名, 配置文件的内容可以参考: *lab-z9/cluster/*.
调度器会根据配置文件的内容将该job拆分为对应机器数量的job, 然后分别提交到
相应的队列中.

那么如何对指定的机器执行指定的测试呢?
在job.yaml中增加这样的内容:

``` yaml
if role <role01>
  <test_script01>:
  <test_script02>:

if role <role02>
  <test_script03>:
  <test_script04>:

...
```

在多机的配置文件中, 会给每台机器赋予一个角色. 当每台机器取得自己队列中的
job时, 按照自己的角色去执行相应角色所对应的脚本.

比如说: 一台多机测试中的机器的角色为*role01*, 那么它会去寻找脚本
*test_script01*, *test_script02*, 然后去执行.

### how to find test script

在lkp-tests的**daemon**, **tests**目录下查找这些脚本.
假设在**daemon**下找到了*test_script01*, 则将该脚本作为`start_daemon`的参
数运行. 如果在**tests**下找到了*test_script01*, 则作为`run_test`的参数去
运行. 如果没有找到相应的文件, 则按变量导出.

### about `start_daemon` and `run_test`

用于启动脚本的这2个函数位于**lkp-tests/lib/job.sh**.
要搞清楚多机的流程, 就得明白这两个函数是怎么去做的.

#### the processes of `start_damon`

  1. 向调度器发送请求`write_state`, 上报机器相关的参数:
	 * `node_roles`: 机器的角色
	 * `ip`: 通过命令`hostname -I`取得的第一个值
	 * `direct_macs`: 多机配置文件中该机器的**macs**字段
	 * `direct_ips`: 调度器根据多机配置文件中的**ip0**字段配置的直连ip, 与
            配置文件中**macs**的值一一对应

  2. 向调度器上报状态`wait_start`，等待返回start：
     调度器记录该机器的状态为: `start`，等待所有节点都进入`start`，向机器返回`start`。
     接收到调度器返回的`start`后，确认所有机器都起来了，

  3. 向调度器发送请求`roles_ip`:
     返回是所有集群节点`write_state`上传的信息，将返回值导出为环境变量.
     将**node_roles**和**ip**写入/etc/hosts
     将**direct_ips**的值一一绑定到机器中的**direct_macs**的相应设备上.

  4. 运行在**daemon**文件夹下找到的脚本。

  5. 向调度器上报状态`wait_ready`，等待返回ready:
     调度器将其记录为: `ready`; 与此同时, 调度器查看是否多机测试中的所有机器都准备好了。
     如果每一台机器都准备好了, 则返回`ready`; 如果其中一台的状态为`abort`, 则返回
     `abort`, 然后退出执行; 其余情况, 则循环查询, 直到前2种情形发生。

  6. 向调度器报告一个状态`wait_finish`, 调度器将其记录为: `finish`; 与
     此同时, 调度器查看是否多机测试中的所有机器的状态都为`finish`。 如果
     都是`finish`, 则返回`finish`; 如果其中一台的状态为`abort`, 则返回
     `abort`, 然后退出执行; 其余情况, 则循环查询, 直到前2种情形发生。

  7. 执行完成.

#### the processes of `run_test`

步骤1,2,3同上述1,2,3

  4. 同上述5，向调度器上报状态`wait_ready`，等待返回ready
  5. 运行在**tests**文件夹下找到的脚本. 运行完成, 向调度器报告一个状态:
     `finished`, 调度器记录为: `finish`; 执行失败, 则报告: `failed`, 调
     度器记录为: `abort`, 然后退出执行.

步骤6,7同上述6,7

调度器记录每台机器各个阶段相关的信息, 可以查看redis的key: **sched/cluster_state** $cluster_id.

#### work flow
```
timeline： -----------------------------------------------------------------------------
server:   wait start     get roles info -- run daemon -- wait ready     wait finish
                    \           /                           \          /             \
                     \         /                              \       /               \
sceduler:              all start                             all ready                 all finish
                     /          \                             /       \                /
                    /            \                           /         \              /
client:    wait start   get roles info ----------------- wait ready     run tests -- wait finish
```

#### others
1. 各个节点直接互信设置，免密登录
  ```
  # ssh根据roles作为主机名免密登录
  >> : jobs/cluster-ssh-trust.yaml
  ```

2. 关于状态请求
`start_daemon`和`run_test`还会报告一个`abort`状态: 循环100次向调度器发
起请求, 查看所有机器是否全部`start`,`ready`或`finish`, 如果循环结束仍然返回的是
`retry`, 则报告该状态, 并结束执行.

但是当调度器接收到与之相关的请求时, 会阻塞(或循环)查询这些机器状态的请求, 因此只
会返回`start`、`ready`、`finish`或`abort`。所以不会触发循环100次请求这个过程, 因
此不会报告`abort`这个状态.
