#### 4.2.3.2 手动制作os_mount=cifs/nfs/local的rootfs

**说明：从本质上来讲，cifs/nfs/local所需的rootfs是可以共用的，所以，如果你制作出了local类型的rootfs，那么cifs/nfs均可以使用此rootfs。**

1. 手动安装iso到物理机A # 此步骤无说明，请自行百度
  - 假设我们安装到的硬盘为/dev/sda
  - 安装完毕，一般会提示“按Enter键重启系统”。
  - 注意：
    - **在重启系统之前，需要设置系统的启动方式为硬盘启动**
      - 目的：对我们安装到/dev/sda的文件系统进行firstboot动作，具体见下

2. firstboot
  - 在1步骤的“按Enter键重启系统”，启动系统后，登录进去，**确认下系统已经安装到硬盘里了，然后直接重启reboot**。
  - 说明：
    - 因为系统在第一次启动的时候会执行一些动作，在其后的系统重启中，不再会执行这些动作。
    - 所以compass-ci需要的rootfs，是执行完这些动作的文件系统，即第二次reboot之后的系统。

3. 将物理机A上的/dev/sda中的系统拷贝到Compass-CI主节点指定目录。
  - 指定目录需要自己创建。如：/srv/os/${os}/${os_arch}/${os_version}-${timestamp} # 时间戳精确到秒。 如：20211210150500
  - 使用物理机A上的非/dev/sda中的系统启动物理机A
    - 使用位于物理机A上的其他硬盘的系统启动物理机A
    - 可以给物理机A提交一个内存文件系统的job（此job不限制os,os_arch,os_version）
  - 在物理机A上，拷贝硬盘A中的系统到Compass-CI主节点的指定目录。
    - 通过nfs/cifs协议挂载你的Compass-CI集群主节点的/srv/os/${os}/${os_arch}/${os_version}-${timestamp}至/mnt1； # rw读写模式
    - 挂在硬盘A至/mnt2
      - 通常安装好的操作系统，会给硬盘A分区，这个时候，每个分区都需要挂载
    - rsync -a /mnt2/. /mnt
      - 如果硬盘A有分区，那么需要按照硬盘A中的文件系统中的/etc/fstab文件定义的分区挂载顺序，来将硬盘A中的分区们中的文件拷贝到Compass-CI主节点指定目录。

4. 对指定目录的rootfs进行一些处理
  - 解压内核并生成${rootfs}/boot/vmlinuz
    - 解压内核(ipxe需要)：如果你的内核格式中有gzip字样，请参考下面的文档
      参考：
      - file: https://gitee.com/wu_fengguang/compass-ci/blob/master/container/qcow2rootfs/bin/common
      - function: unzip_vmlinuz
    - 生成vlinuz软链接（compass-ci代码逻辑需要）：
      ```
      root@z9 /srv/os/openeuler/aarch64/20.03-iso# ll boot | grep vmlinuz
      -rwxr-xr-x  1 root root 7.1M 2021-06-29 20:56 vmlinuz-0-rescue-8f22ff33e906472498de4a5b3fc087ef
      -rw-rw-r--  1 root root  20M 2021-06-29 21:10 vmlinuz-4.19.90-2003.4.0.0036.oe1.aarch64
      lrwxrwxrwx  1 root root   43 2021-06-29 21:10 vmlinuz -> ./vmlinuz-4.19.90-2003.4.0.0036.oe1.aarch64
      ```

  - 生成${rootfs}/boot/modules.cgz（compass-ci代码逻辑需要）
    参考：
    - file: https://gitee.com/wu_fengguang/compass-ci/blob/master/container/qcow2rootfs/bin/common
    - function: create_get_modules

  - 生成${rootfs}/initrd.lkp（compass-ci代码逻辑需要）
    参考：
    - file: https://gitee.com/wu_fengguang/compass-ci/blob/master/container/qcow2rootfs/bin/common
    - function: create_get_initrd

  - 注释掉${rootfs}/etc/fstab的启动项（compass-ci代码逻辑需要）
    参考：
    - file: https://gitee.com/wu_fengguang/lkp-tests/blob/master/tests/iso2rootfs
    - function: disable_fstab

  - 关闭${rootfs}的selinux（compass-ci代码逻辑需要）
    参考：
    - file: https://gitee.com/wu_fengguang/lkp-tests/blob/master/tests/iso2rootfs
    - function: disable_selinux

  - 创建真实版本的软链接（compass-ci代码逻辑需要）
    说明：
    - 需要创建两个软链接`${os_version}`与`${os_version}-iso`。
    - ${os_version}    用于cifs/nfs
    - ${os_version}-iso用于local
    ```
    root@z9 /srv/os/openeuler/aarch64# ll -d 20.03*
    dr-xr-xr-x 1 root root 190 2021-08-24 09:09 20.03-iso-20210824180107
    lrwxrwxrwx 1 root root  29 2021-08-24 18:16 20.03-iso -> 20.03-iso-20210824180107
    lrwxrwxrwx 1 root root  29 2021-08-24 18:16 20.03 -> 20.03-iso
    ```

5. 使用制作出来的rootfs提交job
  ```
  root@localhost ~% submit -m -c borrow-1d.yaml testbox=vm-2p16g os=openeuler os_version=20.03 os_mount=cifs
  root@localhost ~% submit -m -c borrow-1d.yaml testbox=vm-2p16g os=openeuler os_version=20.03 os_mount=nfs
  root@localhost ~% submit -m -c borrow-1d.yaml testbox=vm-2p16g os=openeuler os_version=20.03 os_mount=local
  ```
