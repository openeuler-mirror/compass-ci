#### 4.4.2.1 虚拟机使用cifs/nfs的rootfs流程

虚拟机类型的testbox是通过调用/c/compass-ci/providers/qemu.sh脚本，同时给其传入各种运行时参数，运行起来的。

所以我们分析rootfs如何使用，从这个脚本开始分析。

1. testbox启动并与调度器建立websocket连接，等待job

- /c/compass-ci/providers/qemu.sh
  - functions flow:
    - main()		# 入口方法
      +- 打印一些日志
      +- 申请运行文件锁
      +- 向Compass-CI集群注册该testbox信息
      +- 准备一些变量
      +- 运行/c/compass-ci/providers/qemu/kvm.sh
  - key code:
    source "$CCI_SRC/providers/$provider/${template}.sh"

- /c/compass-ci/providers/qemu/kvm.sh
  - functions flow:
    - check_logfile()	# 准备日志文件（日志系统会使用到）
    - write_logfile()	# 循环与调度器建立websocket连接，如果服务端返回“no job now”，那么继续循环等待，如果服务端返回job，那么跳出等待循环

  - key code:
    ```bash
    url=ws://${SCHED_HOST:-172.17.0.1}:${SCHED_PORT:-3000}/ws/boot.ipxe/mac/${mac}
    ipxe_script_path="$(pwd)/${ipxe_script}"
    command -v ruby &&
            ruby -r "${CCI_SRC}/providers/lib/common.rb" -e "ws_boot '$url','$hostname','$index','$ipxe_script_path'"
    ```
  - 说明：
    - ws_boot()是位于/c/compass-ci/providers/lib/common.rb中的，compass-ci封装的一个方法;
    - ws_boot()运行的一侧，属于客户端，它会与服务端（调度器）建立websocket长连接，请求job；
    - 服务端（调度器）如果半个小时都没有调度到这个客户端的任务，就会给客户端返回包含“no job now”的返回值；
      /c/compass-ci/providers/qemu/kvm.sh中会处理返回值：
      - 如果返回值包含“no job now”，那么继续循环请求job；
    - 服务端（调度器）如果找到了对应的job，会返回给客户端经过组合的返回值。（相当于客户端接收到了job）。
      返回值举例：
      ```
      #!ipxe

      initrd http://172.168.131.113:8000/os/openeuler/aarch64/20.03-2021-05-18-15-08-52/boot/initramfs.lkp-4.19.90-2003.4.0.0036.oe1.aarch64.img
      initrd http://172.168.131.113:8000/os/openeuler/aarch64/20.03-2021-05-18-15-08-52/boot/modules-4.19.90-2003.4.0.0036.oe1.aarch64.cgz
      initrd http://172.168.131.113:3000/job_initrd_tmpfs/crystal.3584856/job.cgz
      initrd http://172.168.131.113:8800/upload-files/lkp-tests/aarch64/v2021.09.23.cgz
      initrd http://172.168.131.113:8800/upload-files/lkp-tests/9f/9f87e65401d649095bacdff019d378e6.cgz
      kernel http://172.168.131.113:8000/os/openeuler/aarch64/20.03-2021-05-18-15-08-52/boot/vmlinuz-4.19.90-2003.4.0.0036.oe1.aarch64 user=lkp job=/lkp/scheduled/job.yaml ip=dhcp rootovl ro root=cifs://172.168.131.113/os/openeuler/aarch64/20.03-2021-05-18-15-08-52,guest,ro,hard,vers=1.0,noacl,nouser_xattr,noserverino  initrd=initramfs.lkp-4.19.90-2003.4.0.0036.oe1.aarch64.img  initrd=modules-4.19.90-2003.4.0.0036.oe1.aarch64.cgz  initrd=job.cgz  initrd=v2021.09.23.cgz  initrd=9f87e65401d649095bacdff019d378e6.cgz rootfs_disk=/dev/vdb crashkernel=auto
      boot
      ```

2. testbox（客户端）接收到job，开始准备环境，执行job

- /c/compass-ci/providers/qemu/kvm.sh

  - functions flow:
    - write_logfile()		# 循环与调度器建立websocket连接，如果服务端返回“no job now”，那么继续循环等待，如果服务端返回job，那么跳出等待循环
    - parse_ipxe_script()	# 下载返回值中的kernel, initrd(s)文件
    - check_kernel()		# 检查kernel文件是否下载成功
    - write_dmesg_flag()	# 插入日志锚点（日志系统会使用到）
    - check_initrds()		# 将所有initrd(s)文件按顺序合并成一个concatenated-initrd文件，供后续启动虚拟机时候调用
    - set_options()		# 准备内核、网卡、磁盘等启动虚拟机所需参数对应的变量
    - print_message()		# 打印一些关键信息，调试用
    - public_option()		# 准备一些qemu的公共参数（与系统架构无关参数）
    - add_disk()		# 创建硬盘
    - individual_option()	# 准备一些qemu的非公共参数（如：系统架构）
    - run_qemu()		# 根据上面准备的参数，启动虚拟机

  - key code:
    ```
    ###################
    # func: run_qemu()
    #       - 使用一些参数启动qemu
    #       - ${append}是从上面解析得来的,请注意上面例子中kernel后面的3个关键字段：
    #         - overlay
    #         - initrd=initramfs.lkp-5.3.18-57-default.img
    #         - root=cifs://172.168.131.113/os/openeuler/aarch64/20.03-2021-05-18-15-08-52,guest,ro,hard,vers=1.0,noacl,nouser_xattr,noserverino
    ###################

    "${kvm[@]}" "${arch_option[@]}" --append "${append}"

    ###################
    # demo
    ###################
    qemu-kvm
        -name guest=vm-2p8g.yuchuan-766969,process=crystal.3592968
        -kernel vmlinuz-4.19.90-2003.4.0.0036.oe1.aarch64
        -initrd concatenated-initrd
        -smp 2
        -m 8G
        -rtc base=localtime
        -k en-us
        -no-reboot
        -nographic
        -monitor null
        -drive file=/home/yuchuan/compass-ci/providers/vm-2p8g.yuchuan-766969-vda.qcow2,media=disk,format=qcow2,index=0,if=virtio
        -drive file=/home/yuchuan/compass-ci/providers/vm-2p8g.yuchuan-766969-vdb.qcow2,media=disk,format=qcow2,index=1,if=virtio
        -machine virt-4.0,accel=kvm,gic-version=3
        -cpu Kunpeng-920
        -bios /usr/share/qemu-efi-aarch64/QEMU_EFI.fd
        -nic tap,model=virtio-net-pci,helper=/usr/libexec/qemu-bridge-helper,br=br0,mac=0a-c4-12-1d-60-5e
        --append 'user=lkp job=/lkp/scheduled/job.yaml ip=dhcp rootovl ro root=cifs://172.168.131.113/os/openeuler/aarch64/20.03-2021-05-18-15-08-52,guest,ro,hard,vers=1.0,noacl,nouser_xattr,noserverino      rootfs_disk=/dev/vdb crashkernel=auto'
    ```
  - 说明：
    - 到此步，我们已经知道了，虚拟机是通过qemu-kvm命令调用起来的，本次job所需的kernel, initrd(s), rootfs均以参数的形式传给了这个命令。
    - 接下来，就到了Compass-CI的自定义化的linux开机启动流程。

- Compass-CI的自定义化的linux开机流程

  - Linux开机流程简要说明：
    - 开机启动内核，内核加载initrd(s)中的所有文件到内存； # initrd(s)所有文件组合起来，会是一个文件系统
    - 在内存中依次执行initrd(s)组成的系统中定义的启动项；
    - 在执行这些启动项的时候，会根据传入的内核命令行参数（也就是${append}），来找到并启动本次要真正使用的文件系统。 # 这一步骤，依然还是在initrd(s)组成的文件系统中
    - 启动本次真正要使用的文件系统。 # 这就是所谓的“切根” —— 使用的根文件系统，从initrd(s)组成的文件系统，“切”到真正要使用的文件系统

  - 对cifs/nfs类型的job：
    - 它真正要使用的文件系统，就是root=cifs://172.168.131.113/os/openeuler/aarch64/20.03-2021-05-18-15-08-52,guest,ro,hard,vers=1.0,noacl,nouser_xattr,noserverino

    - 我们传入的initrd(s)组成的文件系统，包括了当前这台testbox执行分配给它的job所需要的文件； # 如lkp.cgz，job.cgz中的文件
    - 但是这些文件是在initrd(s)组成的文件系统中的，而不在本次要真正使用的文件系统中；
      - 相当于在initrd(s)组成的文件系统（/目录）中，有我们job需要的文件的；
      - 而本次要真正使用的文件系统（/sysroot目录）中，没有我们job需要的文件的； # root=cifs://xxxx会通过指定的协议（cifs/nfs）挂载到/sysroot目录

    - 所以，我们需要把job需要的文件从/目录，拷贝到/sysroot目录。
    - 这个拷贝的动作，是由initrd(s)中的某一个开机启动项来触发的。

    - 在cifs/nfs类型的job，由于我们传入的内核命令行参数中有overlay这个关键字，而overlay这个关键字，对应的有其开机启动项，拷贝的动作就是在这个开机启动项触发的。
    - overlay对应的开机启动项，在默认的initrd中是不支持的，所以我们每做出一个rootfs，都需要通过/c/compass-ci/container/dracut-initrd这个容器来生成一个initrd。
    - 在本例中，就是initrd=initramfs.lkp-5.3.18-57-default.img
    - 而cifs/nfs类型的job，这个拷贝的动作对应的代码，位于：/c/compass-ci/container/dracut-initrd/bin/overlay-lkp.sh

    - 拷贝前：root=cifs://xxxx已经通过指定的协议（cifs/nfs）挂载到/sysroot目录了
    - 拷贝中：job所需要的文件会被拷贝到job真正要使用的文件系统（/sysroot）中
    - 拷贝后：/sysroot是本次要真正使用的文件系统，接下来就是来启动/sysroot中的文件系统。

    - 在这个系统中，已经有我们执行lkp所定义的任务所需要的一系列文件。其中就包括一个关键的系统服务：lkp-bootstrap.service。
    - 所以，在/sysroot中的文件系统执行它自己的开机启动流程时，就能通过lkp-bootstrap.service，来执行我们定义好的job。

- cifs/nfs类型的testbox启动起来之后的系统是什么样子的？
  [cifs/nfs类型testbox启动起来的系统](./demo/cifs.log)
