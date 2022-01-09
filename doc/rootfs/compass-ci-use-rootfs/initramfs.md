### 4.4.4 os_mount=initramfs的rootfs是如何使用起来的

#### 4.4.4.1 虚拟机使用initramfs的rootfs流程

虚拟机使用initramfs的rootfs流程与[虚拟机使用cifs/nfs的rootfs流程](./cifs-nfs-qemu.md)大致相同，我们这里只说不同点。

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
  - initramfs返回值举例：
    ```
    #!ipxe

    initrd http://172.168.131.113:8800/initrd/osimage/openeuler/aarch64/20.03/20210609.0.cgz
    initrd http://172.168.131.113:8000/os/openeuler/aarch64/20.03-2021-05-18-15-08-52/boot/modules-4.19.90-2003.4.0.0036.oe1.aarch64.cgz
    initrd http://172.168.131.113:8800/initrd/deps/initramfs/debian/aarch64/sid/run-ipconfig/run-ipconfig_20201103.cgz
    initrd http://172.168.131.113:8800/initrd/deps/initramfs/openeuler/aarch64/20.03/lkp/lkp_20210906.cgz
    initrd http://172.168.131.113:3000/job_initrd_tmpfs/crystal.3585813/job.cgz
    initrd http://172.168.131.113:8800/upload-files/lkp-tests/aarch64/v2021.09.23.cgz
    initrd http://172.168.131.113:8800/upload-files/lkp-tests/9f/9f87e65401d649095bacdff019d378e6.cgz
    kernel http://172.168.131.113:8000/os/openeuler/aarch64/20.03-2021-05-18-15-08-52/boot/vmlinuz-4.19.90-2003.4.0.0036.oe1.aarch64 user=lkp job=/lkp/scheduled/job.yaml ip=dhcp rootovl ro rdinit=/sbin/init prompt_ramdisk=0  initrd=20210609.0.cgz  initrd=modules-4.19.90-2003.4.0.0036.oe1.aarch64.cgz  initrd=run-ipconfig_20201103.cgz  initrd=job.cgz  initrd=v2021.09.23.cgz  initrd=9f87e65401d649095bacdff019d378e6.cgz rootfs_disk=/dev/vdb crashkernel=auto
    boot
    ```
  - 分析：
    两种os_mount的不同，核心在于传递给kernel的命令行参数不同，而这个不同，会反映在不同点2：Compass-CI的自定义化的Linux启动流程不同

- 不同点2：内核命令行参数不同，导致Compass-CI的自定义化的Linux启动流程不同

  - os_mount=initramfs的系统，会直接使用在内存中解开的initrd(s)启动的系统，没有“切根”步骤
    - initramfs的系统开机流程简要说明：
      - 开机启动内核，内核加载initrd(s)中的所有文件到内存； # initrd(s)所有文件组合起来，会是一个文件系统
      - 在内存中依次执行initrd(s)组成的系统中定义的启动项； # 所以，os_mount=initramfs，它的job的运行环境，是在内存中的一个文件系统。

  - cifs/nfs与local的内核命令行参数相同项：
    - user=lkp
    - job=/lkp/scheduled/job.yaml
    - ip=dhcp
    - initrd=modules-4.19.90-2003.4.0.0036.oe1.aarch64.cgz
    - initrd=job.cgz
    - initrd=v2021.09.23.cgz
    - initrd=9f87e65401d649095bacdff019d378e6.cgz
    - rootfs_disk=/dev/vdb
    - crashkernel=auto
    - rootovl
    - ro

  - cifs/nfs的独立参数项：
    - initrd=initramfs.lkp-4.19.90-2003.4.0.0036.oe1.aarch64.img
      - 这个initrd文件是我们通过/c/compass-ci/container/dracut-initrd容器制作出来的，它包含一个最小化的文件系统，这个文件系统，是debian的。
      - 但是os_mount=initramfs，由于没有切根的动作，所以它不能有debian系统的文件，它需要的是我们本次job真正要使用的文件系统。

    - root=cifs://172.168.131.113/os/openeuler/aarch64/20.03-2021-05-18-15-08-52,guest,ro,hard,vers=1.0,noacl,nouser_xattr,noserverino # root设备使用cifsroot/nfsroot，它会调用95cifs/95nfs这个启动项。
    - 说明：
      - 从数字上95cifs/95nfs，会先于90overlay-root执行。
      - 所以，在initrd(s)的系统启动阶段，会先执行95cifs/95nfs，挂载远程的cifs/nfs服务端的rootfs到/sysroot；
      - 然后执行90overlay-root，会基于/sysroot，再覆盖一层可读写的overlayfs，并将job所需的文件拷贝到这层overlayfs中；
      - 然后将这层可读写的overlayfs作为本次要使用的文件系统，并启动它，开始执行job。

  - initramfs的独立参数项：
    - rdinit=/sbin/init                 # 指定initrd(s)组成的文件系统中，要运行的1号进程
    - prompt_ramdisk=0                  # 如上面我们讲的，os_mount=initramfs对应的文件系统是内存文件系统，所以需要这个参数，来让内核支持内存文件系统
    - initrd=run-ipconfig_20201103.cgz  # 内存文件系统需要initramfs-tools来支持一些功能，比如支持rd.init，支持ipconfig配置ip等... （详情参考：https://manpages.ubuntu.com/manpages/xenial/man8/initramfs-tools.8.html）
    - initrd=20210609.0.cgz             # 这个文件是os_mount=initramfs所对应的rootfs，它里面是本次job所指定的${os},${os_arch},${os_version}的所有文件

    - 说明：
      - os_mount=initramfs没有切根动作，initrd(s)组成的系统直接就是job的执行环境。

#### 4.4.4.2 物理机使用initramfs的rootfs流程

物理机使用initramfs的rootfs流程与[物理机使用cifs/nfs的rootfs流程](./cifs-nfs-hw.md)大致相同，不同点见上面的“虚拟机使用initramfs的rootfs流程”部分的两个不同点。

#### 4.4.4.3 initramfs类型的testbox启动起来之后的系统是什么样子的？

[container类型testbox启动起来的系统](./demo/container.log)
