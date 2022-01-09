#### 4.2.3.3 手动制作os_mount=initramfs的rootfs

1. 将制作出来的相同${os},${os_arch},${os_version}的os_mount=cifs/nfs/local的rootfs拷贝一份到临时目录。
   ```bash
   mkdir /srv/os/openeuler/aarch64/20.03-iso-tmp
   rsync -a /srv/os/openeuler/aarch64/20.03-iso-2021-08-24-18-01-07/. /srv/os/openeuler/aarch64/20.03-iso-tmp/
   ```
2. 进入临时目录，删掉一些不需要加入到initamfs系统的文件

   **说明：也可以不删除这些文件，如果你知道你需要它们**
   ```bash
   cd /srv/os/openeuler/aarch64/20.03-iso-tmp/
   rm -rf lib/modules/*
   rm -rf boot/vmlinuz*
   rm -rf boot/initr*
   ```

 3. 生成initramfs的rootfs
   ```bash
   ############
   # 为什么要去掉${os_version}的-iso后缀：
   # - 目前，只有os_mount=local对应的rootfs需要-iso后缀，initramfs不需要
   ############

   initramfs_cgz=/srv/initrd/osimage/$os/$os_arch/${os_version%-iso}/$(date +"%Y%m%d").0.cgz
   mkdir -p $(dirname $initramfs_cgz)
   cd /srv/os/openeuler/aarch64/20.03-iso-tmp/
   find . |cpio -o -Hnewc | gzip -9 > $initramfs_cgz

   cd $(dirname $initramfs_cgz)
   ln -sf $(basename $initramfs_cgz) current

   ############
   # 如何获得../../../deps/nfs/debian/aarch64/sid/run-ipconfig.cgz：
   # - 从Compass-CI官网下载：https://api.compass-ci.openeuler.org:20008/initrd/deps/nfs/debian/aarch64/sid/
   ############

   ln -sf ../../../deps/nfs/debian/aarch64/sid/run-ipconfig.cgz run-ipconfig.cgz
   ```
