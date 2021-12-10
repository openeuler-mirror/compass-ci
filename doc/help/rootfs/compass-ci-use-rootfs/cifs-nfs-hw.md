#### 4.4.2.2 物理机使用cifs/nfs的rootfs流程

物理机类型的testbox需要设置物理机的首选启动项为PXE，它的运行是从上电启动开始的。

所以我们分析rootfs如何使用，从上电开始分析。

1. testbox启动并与调度器建立websocket连接，等待job

- 物理机上电启动，进入到pxe阶段，pxe阶段会向同一网络发送pxe请求；

- 这时Compass-CI集群提供的dnsmasq服务，会接收到这个pxe请求，返回给物理机一个可用的ipxe驱动下载地址； # 如：/tftpboot/ipxe/bin-arm64-efi/snp.efi

- 物理机拿到并加载ipxe驱动，加载完成后会再次向同一网络发出ipxe请求；

- 这时Compass-CI集群提供的dnsmasq服务，会接收到这个ipxe请求，返回给物理机一个tftp ipxe文件下载地址； # 如：boot.ipxe （此处为相对路径，即文件真实路径：/tftpboot/boot.ipxe）

- 物理机拿到并执行ipxe命令行所组成的boot.ipxe。
  - boot.ipxe内容如下：
    ```
    #!ipxe
    set scheduler 172.168.131.113
    set port 3000

    chain http://${scheduler}:${port}/boot.ipxe/mac/${mac:hexhyp}

    exit
    ```
  - 所以，到此步骤，物理机testbox已经与调度器建立了连接，等待job。

    - 服务端（调度器）如果半个小时都没有调度到这个客户端的任务，就会给客户端返回如下返回值:
      ```
      chain http://#{ENV["SCHED_HOST"]}:#{ENV["SCHED_PORT"]}/boot.ipxe/mac/${mac:hexhyp}"
      ```
      - 物理机接收到此返回值，会继续请求job

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

- 客户端解析并执行服务端（调度器）传回来的返回值，开始启动

  - 服务端传回来的返回值，直接是由ipxe命令组成的字符串，所以，这个字符串会被ipxe直接解析执行
  - 如上面的例子，这个字符串的最后一行是“boot”，所以，物理机此时，会进入Compass-CI自定义化的Linux开机流程。

- Compass-CI的自定义化的linux开机流程
  由于都是os_mount=cifs/nfs，所以，物理机的开机流程与[虚拟机使用cifs/nfs的rootfs流程](./cifs-nfs-qemu.md)部分的开机流程一致。
