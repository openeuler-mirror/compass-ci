- ## 系统架构

  整体架构采用分布式的方式，包括Coordinator、Worker和Aggregator三个主要组件。

  1. **Coordinator（协调节点）：** 负责任务的分配和调度，管理整个系统的状态信息。
  2. **Worker（工作节点）：** 负责更新Git仓库、处理数据。可部署在各个家庭服务器上，无需公网IP。
  3. **Aggregator（聚合节点）：** 负责汇总各个Worker数据，从worker上拉取更新，并提供统一的服务接口给外部用户。Aggregator拥有公网IP，可供外部访问。

  

  ## 组件功能

  1. **Coordinator：**

     - 轻量级节点，拥有公网IP
     - 读取配置文件，管理数据。
     - 负责任务的分配和调度，将Git仓库URL分配给不同的Worker。
     - 与Aggregator交互。

     需要保证Coordinator的轻量级-> 

     1、高效任务调度算法+状态管理（避免不必要的计算和存储开销）

     2、需要保证其设计和功能的简化

     3、异步和并发处理

  2. **Worker：**

     - 从Git托管服务商（如GitHub、GitLab、Gitee）更新Git仓库数据，并实现增量同步。
     - 提供服务接口，响应Aggregator和Coordinator的请求。
     - 将本地状态和数据汇报给Coordinator。

  3. **Aggregator：**

     - 从各个Worker收集数据，并进行汇总。
     - 拥有公网IP，提供统一的服务接口给外部用户，例如提交任务、获取数据等。

  

  > **【worker/aggregator是否可合并? 成为一个模块里的两种运行模式：partial/full模式】**
  >
  > 可行。
  >
  > **Partial模式：** 在Partial模式下充当Worker的角色，负责从上游Git托管服务拉取指定的Git仓库数据并进行增量同步。它会定期轮询上游仓库，根据更新活跃度自适应地执行Git Pull操作频率。此模式下的核心功能是实现Git仓库的增量同步。
  >
  > **Full模式：** 在Full模式下充当Aggregator的角色，负责整体协调和服务提供。它会接收来自Partial模式的数据，并将所有拉取的仓库数据集中在一起。在Full模式中，还包含处理API请求、动态添加/更新Git URL等功能。此模式下的核心功能是对外提供API接口，允许用户按需触发Git仓库的拉取操作，并管理Git仓库的配置信息。

  

  ## 通信方式

  1. **Coordinator与Worker之间：**

     基于低延迟、高性能要求，使用**gRPC**来实现通信。

     

     > 【基本框架流程】
     >
     > 首先coordinator启动等待10min，到时间有一定数量的worker连接之后固定哈希，确定好哈希环结构之后coordinator开始计算每一个worker与repo之间的哈希对应，并且记录下来。
     >
     > 在coor端有维护一个map对应保存worker和urls，在此充当一个**缓冲区**的作用。每次worker向coor发送心跳包，coor会解析获取到workerID，然后在对应的map中查找缓冲区是否为空。是 -- respon返回、清空缓冲区； 否 -- 正常返回respon
     >
     > 之后worker通过解析respon获取一个List，会通过自己维护的urls List对本地仓库进行增加和删除。
     >
     > 
     >
     > 心跳机制的设计主要是worker定期发送心跳包给coordinator，由coordinator去累计一个接收到的心跳包sum，然后每次通过这个总和去判断哪个worker已经很久没有发送心跳包了（设置一个最大限度的查值sumMax）
     >
     > 然后将发送心跳包以及心跳验证的时间频率增大，让心跳包发的频率快点。当有一个worker挂掉时，就可以通过心跳包的response，由coordinator向worker发送“add repo”的通知。

     

  2. **Aggregator与Worker之间：** 

     同样可使用RPC来实现通信。

     Aggregator向Worker请求最新数据

     wfg: Aggregator是否可以直接git fetch方式访问Worker? Worker直接起一个本地git server服务即可。
     **Worker与Aggregator之间建立一种反向代理或隧道。因为Worker没有公网IP，通常Aggregator无法主动直接访问Worker。**

     aggregator => git fetch coordinator port => map to the worker port

     run a port map program in worker, map worker's local port to coordinator port

     (ssh/python) port forward?

     vpn? need root

     

     worker id/token for authenticate

     分发渠道: 微信/email等

     write to config file

     连接认证 https, JSON request with token field

     

     git push to Aggregator?
     安全性 对公众开放 危险 会被攻击

  3. **Coordinator与Aggregator之间：** 

     这两者之间的通信需要更稳定和可靠的公共接口-> 可使用HTTP协议来实现

     Coordinator将从Worker收集到的数据请求发送给Aggregator，Aggregator进行数据汇总和处理后，将结果返回给Coordinator。

  4. **外部用户与Aggregator之间的通信：** 用户可通过HTTP API与Aggregator交互，提交任务、获取数据等操作。

  

  【计算网络带宽】

    worker<>aggregator<>coordinator
    worker<>coordinator speed 10MB/s
    aggregator<>coordinator speed 100MB/s

  

  

  # 数据结构

  ### Coordinator全局变量

  git clone to disk -> read into memory datastruct => git_tree

  1、manage git_urls

  > **a git tree to store git urls - [in memory]**
  >
  > git_urls/
  > dir/files 1000 urls per file
  >
  >    - git_url:
  >      [key: val] 
  >      workers: [worker_id1, worker_id2]
  >      ...
  >    - git_url:

  2、manage workers【urls <> workers mapping】需做持久化

  worker处理：此map中存的是所有与coordinator建立过连接的worker。

  - should
  - real【？存两份的意义？】

  =>  diff =>tell workers in small batches

  ​	1）alloc_worker_bitmap -> worker_id

  ​	2）worker_map[worker_id]：

  ```json
  value {
  	// key: worker_id => use 【bitmap】 to alloc
  	pub_ip_addr:     //  only aggregator have
  	role: worker/aggregator  // also includes aggregator
  	status: alive/done
  	last_alive_time:
  }
  ```

  3、add_repo/delete_repo-> fetch upstream_urls_repo获得的增加/删减的仓库，根据hash算出对应的worker，告诉worker添加对该repo的监听

  

  ### Worker全局变量

  自己维护repo的元数据（需要存一份本地日志文件）（主要为了优先级pri服务，不需要持久化）

  一个worker挂了，coordinator将当前此worker上维护的repo下发给其他worker（较为平均），此时只需要将其他元数据置0，pri置为max（从pri_queue中获取max pri）

  **元数据**

  => coordinator_ip_addr (read config file)

  => git_repos_map[repo_url]

  ```
  struct repo_url {
      push_interval:
      clone_fail_cnt:
      fetch_fail_cnt:
      queue: true/false  // 判断是否在任务队列中【?】
      ...
  }
  ```

  => git_queue 任务队列

  => priority_queue 优先级队列

  

  

  

    ## 启动流程

    - #### coordinator

  cood_config_file:
  	listen port
  	git_urls git repo url

  local disk space:
  	git_urls git repo

  startup:
      **read cood_config_file** -> ( git clone/fetch/update urls_git_repo ) 
      load all git_urls git content to memory、create data structure （git_tree）in memory

  ​	load worker cache ( status...)

  ​	( if cache no null => ) send keepalive to refresh workers's status

  ​	( if cache is null => ) wait for 10 min（等待worker连接）

  ​	根据hash 分发repo给worker

  **event loop:**
  	on worker register: listen => add_worker
  	on worker register its local urls:  worker use rpc to register

  **send_keepalive**（new thread-> on time）

  func:
  	**monitor_git_urls** （new thread-> git fetch urls_git_repo on time）:

  ```ruby
          loop:
              fetch_info = %x(git -C #{urls_git_repo} fetch)
              if fetch_info.include('->') # have new commit
              # 如何知道哪部分增量(repo变动)添加了？-> parse_log_changes(add_repo,delete_repo)
              # git show-> get +/- lines
              parse_log_changes(add_repo,delete_repo)
  	    for added repos: # 处理添加的repo
  	        worker = repo_hash_worker(add_repo)
              tell worker to add repo
  	    for deleted repos: # 处理删除的repo
              worker = repo_hash_worker(delete_repo)    
              tell worker to del repo
  ```

  ​	**parse_log_changes(add_repo,delete_repo)**

  => simplify to check HEAD changes

  ​			wfg /c/cci/lab-z9% cat .git/HEAD

  ​			ref: refs/heads/master

  ​			wfg /c/cci/lab-z9% cat .git/refs/heads/master

  ​			f14340c0acab3034132b32010f64492363fef3c3

  ​			wfg /c/cci/lab-z9% git log -1 HEAD

  ```ruby
  	%x(git show)
  	# 开始解析git show内容 -> 通过判断add/delete来判断，其他情况就是update
  	# 1、diff后面解析出变更仓库，然后从git_tree上找/对比
  	# 2、判断add/delete，其他情况就是update
  	# 3、保存对应信息
  ```

  

  ​	**add_worker(new_worker_id)** => 当有worker与coordinator建立连接时触发

  ```ruby
  	next_worker = worker_map[new_worker_id].next
  	fix_repo = get_fix_hash() # 得到需调整的repo哈希区间
  	add_repo(fix_repo, new_worker_id) 	# 将fix_repo在新worker中处理克隆好-> git clone fix_repo
  	re-assign urls to each worker
  	# 异步处理[use coroutine]
  ```

  - -> **add_repo()**

  ```ruby
  	# 1、loop: scan/send a batch of urls to worker; sleep
  	# 2、over
      
  worker： git clone -> over：send rpcMsg to coordinator
  
  coordinator：recevie rpcMsg-> 解析消息体type-> 
  	delete_repo(fix_repo, next_worker)	# 再将原本worker中的fix_repo移除【以此解决repo抖动问题】
  	revise_hash()	# 修改hash
  ```

  **delete_worker** => 当有worker挂了时触发

  ```ruby
  	hash_split_repo()	# hash均分repo给其他worker
  	-> add_repo()		# 中途会涉及add_repo操作
  	delete:worker_map[worker_id]	# 把worker从worker_map中移除
  	# no delete: 记下来即可，加一个字段，加时间，加历史，方便delect 频繁up/down的不稳定节点
  ```

  

  

   - #### worker

  config file:
  	where is coordinator
  	disk path

  git repos disk layout:
    	raw local git repos

  in-memory data:
    	git urls that have raw local git repos挂机

  startup:
      connect to coordinator
      scan per-url git dir, get local_urls list
      tell coordinator

  event loop:
      on add new url request: get from coordinator new urls to process
      on del old url request: 
      on fetch old url request: do local git fetch
  	on ping request: receive keepalive request -> ack to coordinator

  func:
  	**fetch_repo**:
  		if found git url 404
  				API tell coordinator
  		if network error
  				arrange local retries
  		if disk error
  				API tell coordinator I'm down

  ​	**receive_keepalive**

  ​	**add_repo / delete_repo**

  

  


   - #### aggregator

     scan per-url git dir, get local_urls list &
     connect to coordinator
     report local_urls list to coordinator

  

  

  

  ## 仓库下发worker机制【func: repo_hash_worker】

  Coordinator中存有仓库URL list，采用一致性哈希算法来分配对应的worker。

  由于在分布式集群中worker节点的个数会不定时调整（增加n个worker或n个worker挂机的情况），如果采用常规哈希，在面对节点数量变化时选择重新去仓库列表源Coordinator中大规模进行仓库的重新分配，效率会很低且耗时间。

  考虑节点数量变化的场景，可以采用一致性哈希算法去解决。

  

  将repo哈希值映射到0-n空间中，且将这个范围首尾相连形成一个环。再解决worker负载不均的问题（当worker数量少时，有种情况是如果当前workerA挂了，那么原本workerA维护的n个仓库将全部由顺时针的下个workerB进行维护，导致负载不均），在一致性哈希的基础上引入虚拟worker的概念，一个真实worker对应n个虚拟worker。代价非常小，只需增加一个map维护真实节点与虚拟节点的映射关系即可。

  映射过程如下：

  Coordinator给出一个URL-> hash-> 对应到对应的worker

  hash过程如下：

  - 计算虚拟worker(使用worker的IP地址)的哈希值，放在环上。
  - 计算仓库（使用仓库URL）的哈希值，对哈希值进行判断-> 顺时针寻找到的第一个节点，就是应选取对应的worker。

  *（可参考图“一致性哈希.png”，其中key即为repo，peer即为worker）*

  ![](https://github.com/yanyanran/pictures/blob/main/%E4%B8%80%E8%87%B4%E6%80%A7%E5%93%88%E5%B8%8C.png?raw=true)

  ##### 插入新worker后，旧worker.next上的仓库是否需要取消其在worker上的维护？ => 需要

  - insert new worker

  ​	traverse hash repo：new_worker.pre-> new_worker之间

  ​		【coordinator修改映射】 (1by1事务) delete hash in new_worker.next => add hash in new_worker

  ​		【send to worker修改worker内部维护的repo list】send rpc -> [new_worker]add_repo、[new_worker.next]delete_repo

  

  ##### 防止repo抖动(thrashing)处理

  alive/active workers detection reliably

  1. coordinator初次启动时，先等待一段时间(10min)，小批次分发任务，逐步增加
  2. 之后每次coordinator启动时，先读取缓存信息(active workers等)，使用之
  3. 【coordinator对每一个worker挂机，先等待一段时间(10min)】，无响应才将repo remove重新分配给其他worker

  -> 这块需要再考虑一下

  

  关于组件之间的通信=> 统一使用远程过程调用（grpc）：

  在coordinator本地注册处理函数，worker发送对应请求即可触发对应函数

  

  

  

  ##  POLL interval 自适应算法

  可延用git-mirror.rb中的逻辑在各worker中【优先级和优先级队列结合】

  同步任务队列**git_queue**<->优先级队列**priority.queue**

  worker_main_loop：

  ​		priority.queue.pop【从优先队列delete_min】-> 

  ​			push_git_queue【放入任务队列】-> 

  ​				get_repo_priority【计算新优先级】-> 

  ​					priority.queue.push 【放回优先级队列】

  new_10_threads：git_queue.pop【从任务队列中取任务进行处理】

  ```c
  STEP_SECONDS = 2592000 // 每个步骤的时间间隔
  
  func get_repo_priority(git_repo, old_pri) {
      mirror_dir = find .git file
  	step = (git_repo.clone_fail_cnt + 1) * cbrt(STEP_SECONDS)  // clone_fail
      if(mirror_dir == null) {
          return old_pri + step  // 仓库未克隆
      }
      return cal_priority(mirror_dir, old_dir, git_repo)
  }
  
  func cal_priority(mirror_dir, old_pri, git_repo) {
      last_commit_time = ...
      step = (git_repo.fetch_fail_cnt + 1) * cbrt(STEP_SECONDS) // fetch_fail
      if(last_commit_time == 0) {
          return old_pri + step  // 没进行过提交
      }
      
      interval = nowTime - last_commit_time
      if(interval <= 0) {
          
          return old_pri + step
      }
      return old_pri + cbrt(interval)
  }
  ```

  通过这种方式保持最近更新的仓库优先级较高（数值越小优先级越高），通过每次+step防止优先级饥饿问题

#### 	worker

  - repo_urls to poll
  - git_repos[repo_url].push_interval # 历史可统计的，上游软件push的间隔
    => log or sqrt (git_repos[repo_url].push_interval)【pri累加的方法能保持平均和公平】
  - github/gitee rate limit # 常数【?】
    =>
  - git_repos[repo_url].poll_interval = A * B / C






  ## 故障检测和自动恢复机制

 【crash, disk down, network down】 

 1、 coordinator  crash

  

 2、 worker  crash

不从coordinaptor维护的worker map中删除，仅将worker状态由alive置为done并记录当前时间作为worker的last_alive_time。

​	为减少trashing：在coordinator监测到worker挂后，开启一个倒计时【绿色线程/协程】

​		=> 超时时间内worker重新连接：照旧运行

​		=> 超时worker未上线：【hash】coordinator将当前此worker上维护的repo下发给其他worker（分配较为平均），并将这些repo在对应的worker中的优先级pri值设为最小（防止优先级饥饿）



3、Aggregator  crash



4、disk down



5、network down





  ## Config_file

  ...

 

  

  

  

## **功能列表：**

  **Story 1: Pull Upstream Repo**

  **Story 2: GitHub Webhook**

  - 功能：通过GitHub的Webhook机制实现Git仓库的自动同步。
  - 包含的操作：
    - 注册GitHub Webhook，将仓库的更新事件推送到系统中。
    - 根据接收到的Webhook消息，识别出哪个Git仓库有更新。
    - 触发相应的Worker执行Git Pull操作，拉取更新的数据。
  - 输入：GitHub Webhook消息（包含更新的Git仓库URL等信息）
  - 输出：无（触发Git Pull操作）

  **Story 3: On Demand (API)**

  - 功能：提供API接口，允许外部用户按需触发Git仓库的拉取操作。
  - 包含的操作：
    - 设计API接口，接收外部用户提交的Git仓库URL和拉取请求。
    - 根据API请求，将拉取任务分配给合适的Worker进行处理。
    - Worker执行Git Pull操作，获取最新的仓库数据，并将结果返回给用户。
  - 输入：外部用户提交的拉取任务请求（包含Git仓库URL和其他相关信息）

  - 输出：任务状态和结果数据。

  **Story 4: Dynamic Add/Update Git URLs (API)**

  - 功能：提供API接口，允许动态添加或更新需要拉取的Git仓库URL。
  - 包含的操作：
    - 设计API接口，接收外部用户提交的Git仓库URL和相关信息。
    - 将新的Git仓库URL添加到系统中，或者更新已有的Git仓库URL的相关信息。
    - 根据情况将新增或更新的Git仓库URL分配给合适的Worker进行处理。
  - 输入：外部用户提交的Git仓库URL和相关信息
  - 输出：Git仓库的添加/更新状态信息。 

​    

  DFX列表
  config file form?

  1M urls store in a git tree
  1 file store 1000 url?
  1k files, each file 1k urls, 100kb per file
  100MB data
  only coordinator git clone urls config file 
  disk data, dir layout





1. Coordinator分配任务给不同的Worker
2. Worker更新Git仓库
3. Worker执行Git Pull操作后，将本地状态和数据汇报给Coordinator
4. Coordinator处理任务结果（返回给Aggregator或者直接处理）
5. Aggregator汇总数据
6. 用户通过Aggregator用户获取数据
7. GitHub Webhook支持