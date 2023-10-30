---
标题:     基于iso制作rootfs
类别:     流程设计
摘要:     操作系统开源社区或OSV厂商通常会提供iso系统镜像，此镜像需要经过安装才能够使用，过程较长且不利于测试环境快速准备
作者:     王国铨

### 背景与动机
操作系统开源社区或OSV厂商通常会提供iso系统镜像，此镜像需要经过安装才能够使用，过程较长且不利于测试环境快速准备。
为了提升测试效率，加快环境部署。

### 对openeuler的价值
提升社区开发者及社区运作者在执行任务时的环境准备效率


### 角色
- 测试工程师
- 构建工程师
- 社区开发者

### openeuler iso->rootfs
 命令支持-h --help查询帮助
  ```
[root@10 container]# ./iso2rootfs --help
Usage: iso2rootfs -d <Dist> -r <Release> [-f] <Iso> [-p] [/path/virt-x-dir/]
Example: iso2rootfs -d openeuler -r 22.03-lts

  ```
检测是否存在qcow2rootfs命令，如果存在则用qcow2rootfs生成tar.gz；然后创建临时的initramfsDir目录；将gz文件在initramfsDir目录中解压；创建initramfs镜像文件的命令，将当前目录及其子目录下的所有文件和文件夹通过管道传递给cpio命令，然后将其打包成一个新c格式的cpio归档文件，接着，通过gzip命令将归档文件压缩成gzip格式，并将压缩后的文件保存为指定路径下的initramfs.img文件。
若不存在qcow2rootfs命令，则采用virt-tar-out的 命令获取rootfs。
  ```
 groups $(whoami) | grep -E "(kvm|qemu|root)"
    if [[ $? -eq 0 && -f $EXTRACT_CMD ]]; then
        # By default, Using qcow2rootfs's way to get rootfs
        echo "Converting .[raw|qcow2] to .tar.gz, please wait several minutes..."
        su - "${whoami}" -c "export LIBGUESTFS_BACKEND=direct | $EXTRACT_CMD $FILE_NAME $FILE_NAME-rootfs.tar.gz"
        echo "Converting .tar.gz to initramfs.img, please wait several minutes..."
        mkdir initramfsDir
        tar -xzvf $FILE_NAME-rootfs.tar.gz -C initramfsDir
        pushd initramfsDir
        find . | cpio -o -H newc | gzip > $(dirname $FILE_NAME)/$FILE_NAME-initramfs.img
        popd
        rm -rf initramfsDir
    else
	echo "Using virt-tar-out to get rootfs..."
        virt-builder --get-kernel "$FILE_NAME"
        virt-tar-out -a "$FILE_NAME" / "$FILE_NAME-rootfs.tar"
    fi
  ```

  ```
[root@10 iso2rootfs]# ./run -d openeuler -r 22.03-lts-sp1 -f /sdb/openEuler-22.03-LTS-SP1-x86_64-dvd.iso -p /root/rpmbuild/BUILD/libguestfs-1.40.2/builder
  ```

