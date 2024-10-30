### 4.4.1 os_mount=container的rootfs是如何使用起来的

os_mount=container的rootfs会被docker类型的testbox使用，docker类型的testbox是通过调用/c/compass-ci/providers/docker.rb脚本，同时给其传入各种运行时参数，运行起来的。

所以我们分析rootfs如何使用，从这个脚本开始分析。

1. testbox启动并与调度器建立websocket连接，等待job

- /c/compass-ci/providers/docker.rb
  - key code:
    ```ruby
    require_relative './docker/docker'
    main(ENV['hostname'], ENV['queues'], ENV['uuid'], ENV['index'])	# 入口方法
    ```

- /c/compass-ci/providers/docker/docker.rb
  - functions flow:
    - main()		# 供外部调用的入口方法
      +- 准备一些变量
      +- 准备目录
      +- 申请运行锁
      +- 向Compass-CI集群注册该testbox信息
      +- 调用parse_response()方法
    - parse_response()	# 循环与调度器建立websocket连接，如果服务端返回“no job now”，那么继续循环等待，如果服务端返回job，那么跳出等待循环

  - key code:
    ```ruby
    require_relative '../lib/common'
    ...omit...
    response = ws_boot(url, hostname, index)
    ```
  - 说明：
    - ws_boot()是位于/c/compass-ci/providers/lib/common.rb中的，compass-ci封装的一个方法;
    - ws_boot()运行的一侧，属于客户端，它会与服务端（调度器）建立websocket长连接，请求job；
    - 服务端（调度器）如果半个小时都没有调度到这个客户端的任务，就会给客户端返回包含“no job now”的返回值；
      /c/compass-ci/providers/docker/docker.rb中会处理返回值：
      - 如果返回值包含“no job now”，那么继续循环请求job；
    - 服务端（调度器）如果找到了对应的job，会返回给客户端经过组合的返回值。（相当于客户端接收到了job）。
      返回值举例：
      ```
      {"job_id"=>"crystal.3583794", "docker_image"=>"centos:7", "initrds"=>"[\"http://172.168.131.113:3000/job_initrd_tmpfs/crystal.3583794/job.cgz\",\"http://172.168.131.113:8800/upload-files/lkp-tests/aarch64/v2021.09.23.cgz\",\"http://172.168.131.113:8800/upload-files/lkp-tests/9f/9f87e65401d649095bacdff019d378e6.cgz\"]"}
      ```

2. testbox（客户端）接收到job，开始准备环境，执行job

- /c/compass-ci/providers/docker/docker.rb
  - functions flow:
    - parse_response()	# 循环与调度器建立websocket连接，如果服务端返回“no job now”，那么继续循环等待，如果服务端返回job，那么跳出等待循环
    - main()		# 供外部调用的入口方法
      +- 调用parse_response()方法
      +- 插入日志锚点（日志系统会使用到）
      +- 下载initrd(s)文件
      +- 调用start_container()方法
    - start_container()	# 启动容器
  - key code:
    ```ruby
    ###################
    # hash: 是服务端返回值解析而来的字典
    #       - 如上例: "docker_image"=>"centos:7"
    ###################

    def start_container(hostname, load_path, hash)
      docker_image = hash['docker_image']
      system "#{ENV['CCI_SRC']}/sbin/docker-pull #{docker_image}"
      system(
        { 'job_id' => hash['job_id'],
          'hostname' => hostname,
          'docker_image' => docker_image,
          'load_path' => load_path,
          'log_dir' => "#{LOG_DIR}/#{hostname}" },
        ENV['CCI_SRC'] + '/providers/docker/run.sh'
      )
      clean_dir(load_path)
    end
    ```

- /c/compass-ci/sbin/docker-pull
  - functions flow:
    main() > local_repository()
  - key code:
    ```bash
    docker pull $DOCKER_REGISTRY_HOST:$DOCKER_REGISTRY_PORT/$image_name 2> /dev/null
    ```
  - 说明：
    - 到此步，Compass-CI集群的docker registry里面的os_mount=container的rootfs（docker image），就被pull到执行机本地了。

- /c/compass-ci/providers/docker/run.sh
  - key code:
    ```bash
    docker run
        ...omit...
        ${docker_image}
    ```
  - 说明：
    - 到此步，Compass-CI集群的docker registry里面的os_mount=container的rootfs（docker image），就被使用起来了。

    - 在这个系统中，已经有我们执行lkp所定义的任务所需要的一系列文件。其中就包括一个关键的系统服务：lkp-bootstrap.service。
    - 所以，在/sysroot中的文件系统执行它自己的开机启动流程时，就能通过lkp-bootstrap.service，来执行我们定义好的job。

- container类型的testbox启动起来之后的系统是什么样子的？
  [container类型testbox启动起来的系统](./demo/container.log)
