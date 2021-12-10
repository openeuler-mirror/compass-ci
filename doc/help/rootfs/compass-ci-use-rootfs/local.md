### 4.4.3 os_mount=local的rootfs是如何使用起来的

os_mount=local的rootfs会被虚拟机/物理机类型的testbox使用，虚拟机与物理机类型的testbox的启动方式不同，所以分开来讲。

#### 4.4.3.1 虚拟机使用local的rootfs流程

虚拟机使用local的rootfs流程与[虚拟机使用cifs/nfs的rootfs流程](./cifs-nfs-qemu.md)大致相同，我们这里只说不同点。

- 不同点1：调度器的返回值不同
  - cifs/nfs返回值举例：
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
  - local返回值举例：
    ```
    #!ipxe

    initrd http://172.168.131.113:8000/os/openeuler/aarch64/20.03-iso-2021-08-24-18-01-07/boot/initramfs.lkp-4.19.90-2003.4.0.0036.oe1.aarch64.img
    initrd http://172.168.131.113:8000/os/openeuler/aarch64/20.03-iso-2021-08-24-18-01-07/boot/modules-4.19.90-2003.4.0.0036.oe1.aarch64.cgz
    initrd http://172.168.131.113:3000/job_initrd_tmpfs/crystal.3584978/job.cgz
    initrd http://172.168.131.113:8800/upload-files/lkp-tests/aarch64/v2021.09.23.cgz
    initrd http://172.168.131.113:8800/upload-files/lkp-tests/9f/9f87e65401d649095bacdff019d378e6.cgz
    kernel http://172.168.131.113:8000/os/openeuler/aarch64/20.03-iso-2021-08-24-18-01-07/boot/vmlinuz-4.19.90-2003.4.0.0036.oe1.aarch64 user=lkp job=/lkp/scheduled/job.yaml ip=dhcp local use_root_partition= save_root_partition= os_version=20.03-iso os_lv_size=10G os_partition= rw root=172.168.131.113:/os/openeuler/aarch64/20.03-iso-2021-08-24-18-01-07  initrd=initramfs.lkp-4.19.90-2003.4.0.0036.oe1.aarch64.img  initrd=modules-4.19.90-2003.4.0.0036.oe1.aarch64.cgz  initrd=job.cgz  initrd=v2021.09.23.cgz  initrd=9f87e65401d649095bacdff019d378e6.cgz rootfs_disk=/dev/vdb crashkernel=auto
    boot
    ```
  - 分析：
    两种os_mount的不同，核心在于传递给kernel的命令行参数不同，而这个不同，会反映在不同点2：Compass-CI的自定义化的Linux启动流程不同

- 不同点2：内核命令行参数不同，导致Compass-CI的自定义化的Linux启动流程不同
  - cifs/nfs与local的内核命令行参数相同项：
    - user=lkp
    - job=/lkp/scheduled/job.yaml
    - ip=dhcp
    - initrd=initramfs.lkp-4.19.90-2003.4.0.0036.oe1.aarch64.img
    - initrd=modules-4.19.90-2003.4.0.0036.oe1.aarch64.cgz
    - initrd=job.cgz
    - initrd=v2021.09.23.cgz
    - initrd=9f87e65401d649095bacdff019d378e6.cgz
    - rootfs_disk=/dev/vdb
    - crashkernel=auto

  - cifs/nfs的独立参数项：
    - rootovl	# 这个参数项会让dracut的90overlay-root，这一开机启动项执行
    - ro      # root设备以只读模式挂载，因为有了rootovl，所以我们job对于系统所有的操作，都是在overlay的upper层进行的，并不会影响远程挂载的nfs/cifs服务端的文件
    - root=cifs://172.168.131.113/os/openeuler/aarch64/20.03-2021-05-18-15-08-52,guest,ro,hard,vers=1.0,noacl,nouser_xattr,noserverino # root设备使用cifsroot/nfsroot，它会调用95cifs/95nfs这个启动项。
    - 说明：
      - 从数字上95cifs/95nfs，会先于90overlay-root执行。
      - 所以，在initrd(s)的系统启动阶段，会先执行95cifs/95nfs，挂载远程的cifs/nfs服务端的rootfs到/sysroot；
      - 然后执行90overlay-root，会基于/sysroot，再覆盖一层可读写的overlayfs，并将job所需的文件拷贝到这层overlayfs中；
      - 然后将这层可读写的overlayfs作为本次要使用的文件系统，并启动它，开始执行job。

  - local的独立参数项：
    - local                # 这个参数项是我们自定义的 ，它会让我们给initrd(s)的系统中自定义的的开机启动项90lkp被调用
    - use_root_partition=  # 这个参数项是我们自定义的 ，它会被90lkp捕获并解析使用
    - save_root_partition= # 这个参数项是我们自定义的 ，它会被90lkp捕获并解析使用
    - os_version=20.03-iso # 这个参数项是我们自定义的 ，它会被90lkp捕获并解析使用
    - os_lv_size=10G       # 这个参数项是我们自定义的 ，它会被90lkp捕获并解析使用
    - os_partition=        # 这个参数项是我们自定义的 ，它会被90lkp捕获并解析使用
    - rw                   # root设备以读写模式挂载，这个参数只会在高级用户需要自定义ipxe命令行，且指定的root设备直接是某一块需要可读写的块设备时用到
    - root=172.168.131.113:/os/openeuler/aarch64/20.03-iso-2021-08-24-18-01-07 # 这个是固定的，一方面会执行95nfs，另一方面，在之后的90lkp也会用到它
    - 说明：
      - 关于90lkp，请见：/c/compass-ci/container/dracut-initrd/modules.d/90lkp
      - 从数字上95nfs，会先于90lkp执行。
      - 所以，在initrd(s)的系统启动阶段，会先执行95nfs，挂载远程的nfs服务端的rootfs到/sysroot（实际上并不会用到它）；
      - 然后执行90lkp，会根据传入的内核命令行参数（包括root），来将root对应的rootfs拷贝到指定格式的lv中； # 详见：/c/compass-ci/container/dracut-initrd/bin/set-local-sysroot.sh
      - 然后将这个lv作为本次要使用的文件系统，并启动它，开始执行job。


#### 4.4.3.2 物理机使用local的rootfs流程

物理机使用local的rootfs流程与[物理机使用cifs/nfs的rootfs流程](./cifs-nfs-hw.md)大致相同，不同点见上面的“虚拟机使用local的rootfs流程”部分的两个不同点。

