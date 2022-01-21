# Multi-device Test

在进行多台机器测试的时候, 需要搭建多台机器的环境.

## When to using multi-device

  * 当被测试程序需要启动一个守护进程时，例如mysql的server端
  * 当执行测试时需要访问另外的机器时，例如mysql的测试脚本需要连接mysql的server端

## How to run a multi-device test

在要提交的job.yaml中, 需要一个**cluster**字段, 它的值是一个多机环境的配置文件的文件名, 配置文件的内容可以参考: **lab-z9/cluster/**

调度器会根据配置文件的内容将该job拆分为对应机器数量的job, 然后分别提交到
相应的队列中.

那么如何对指定的机器执行指定的测试呢?

在job yaml中增加这样的内容:

``` yaml
if role <role01>
  <script01>:
  <script02>:

if role <role02>
  <script03>:
  <script04>:

...
```

在多机的配置文件中, 会给每台机器赋予一个角色. 当每台机器取得自己队列中的
job时, 按照自己的角色去执行相应角色所对应的脚本.

比如说: 一台多机测试中的机器的角色为*role01*, 那么它会去寻找脚本
*script01*, *script02*, 然后去执行。

### how to find test script

在lkp-tests的**daemon**, **tests**等目录下查找这些脚本。

假设在**daemon**下找到了*script01*,则将该脚本作为daemon程序后台运行，把脚本名传给**start_daemon**执行。

如果在**tests**下找到了*script01*, 则作为测试脚本去
运行，把脚本名传给**run_test**执行。

如果没有找到相应的文件, 作为变量使用。

### 关于 `start_daemon` 和 `run_test`

用于启动脚本的这2个函数位于**lkp-tests/lib/job.sh**。

要搞清楚多机的流程, 就得明白这两个函数是怎么去做的。

#### the processes of `start_damon`

  1. 向调度器发送请求`write_state`, 上报机器相关的参数:
	 * `node_roles`: 机器的角色
	 * `ip`: 通过命令`hostname -I`取得的第一个值
	 * `direct_macs`: 多机配置文件中该机器的**macs**字段
	 * `direct_ips`: 调度器根据多机配置文件中的**ip0**字段配置的直连ip, 与
            配置文件中**macs**的值一一对应

  2. 向调度器上报状态`wait_start`，挂起等待返回start。

     调度器记录该机器的状态为: `start`，等待所有节点都进入`start`，向机器返回`start`。
     
     接收到调度器返回的`start`后，确认所有机器都起来了，

  3. 向调度器发送请求`roles_ip`。
     
     返回是所有集群节点`write_state`上传的信息，将返回值导出为环境变量。

     将**node_roles**和**ip**写入/etc/hosts
     
     将**direct_ips**的值一一绑定到机器中的**direct_macs**的相应设备上.

  4. 运行在**daemon**文件夹下找到的脚本。

  5. 向调度器上报状态`wait_ready`，等待返回ready。
  
     调度器将其记录为: `ready`; 与此同时, 调度器查看是否多机测试中的所有机器都准备好了。
     
     - 如果每一台机器都准备好了, 则返回`ready`。
     - 如果其中一台的状态为`abort`, 则返回`abort`, 然后退出执行。
     - 其余情况, 则循环查询, 直到前2种情形发生。

  6. 向调度器报告一个状态`wait_finish`, 调度器将其记录为: `finish`。
    
     与此同时, 调度器查看是否多机测试中的所有机器的状态都为`finish`。
     
     - 如果都是`finish`, 则返回`finish`;       
     - 如果其中一台的状态为`abort`, 则返回`abort`, 然后退出执行; 
     - 其余情况, 则循环查询, 直到前2种情形发生。

  7. 执行完成.

#### the processes of `run_test`

  步骤1,2,3同上述1,2,3

  4. 同上述5，向调度器上报状态`wait_ready`，等待返回ready
  5. 运行在**tests**文件夹下找到的脚本. 运行完成。   
     - 向调度器报告一个状态:`finished`, 调度器记录为: `finish`; 
     - 执行失败, 则报告: `failed`, 调度器记录为: `abort`,然后退出执行。

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

`start_daemon`和`run_test`在lkp-tests代码里的逻辑想要报告一个`abort`状态。
这个逻辑是这样的：

    循环100次向调度器发起请求,查看所有机器是否全部`start`,`ready`或`finish`,
    如果循环结束仍然返回的是`retry`, 则报告该状态, 并结束执行.

但是当调度器接收到与之相关的请求时, 会阻塞(或循环)查询这些机器状态的请求, 因此只
会返回`start`、`ready`、`finish`或`abort`。

所以不会触发循环100次请求这个过程, 因此不会主动报告`abort`这个状态.

## 多机测试实际操作

###  环境准备

1. 准备提交的yaml文件，以iperf.yaml为例,

	```
	suite: iperf
	category: benchmark

    # 集群节点配置文件，需要放在lkp-tests/cluster/cs-s1-a122-c2下
	cluster: cs-s1-a122-c2    

	if role server:
	    # server需要执行的用例，需要准备用例脚本：lkp-tests/daemon/iperf-server
	   iperf-server:

	if role client:		  
	    # client需要执行的用例，需要准备用例脚本：lkp-tests/tests/iperf
	   iperf:
		protocol:
		- tcp
    ```


2. 准备集群节点配置文件，lkp-tests/cluster/cs-s1-a122-c2

    ```
    # 物理机多机测试时需配置，表示配置ip的偏移量，可以使用默认1
    ip0: 1						 
    
    nodes:
        # server执行任务队列名，进入vm-2p32g-multi-node的任务队列执行
        vm-2p32g-multi-node--1:    			 
            # node角色
        	roles: [ server ]
        	
        	# 物理机多机测试时需配置，需要指定具体mac配置ip
        	macs: [ "00:00:00:00:00:00" ]    
        
        # client执行任务队列名，进入vm-2p32g-multi-node的任务队列执行
        vm-2p32g-multi-node--2:
        	roles: [ client ]
        	macs: [ "00:00:00:00:00:00" ]   		 
    ```

    > vm-2p32g-multi-node--1 后面的“--[0-9]”是队列编号，使不同node使用可以相同队列，真正的执行队列是vm-2p32g-multi-node
    
    >目前使用虚拟机测试时只可以使用vm-2p32g-multi-node和vm-2p16g-multi-node两个队列。
    >
    >物理机测试时使用multi-node任务队列
    
    >物理机的mac地址可在lab-z9/hosts下查看

3. 编写测试脚本，多机测试需要用到不同的node的ip，编写测试测试用例的时候需要自行执行连接的ip。

其ip已被export进环境变量，脚本的可执行使用。其变量名为 "direct\_${server}\_ips" , ${server} 为集群配置文件里的roles。



### 提交任务

上述环境准备好之后，提交任务即可。testbox为vm-2p32g或者vm-2p16g

```
submit -m -c iperf.yaml testbox=vm-2p32g
```
