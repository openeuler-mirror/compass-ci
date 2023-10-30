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


### story

1. 给定执行环境的iso (url)，快速加载执行环境
   - 查看当前是否已经存在iso的rootfs，如果有直接加载，没有执行下一步。（非本方案重点）
   - 下载iso，执行iso转rootfs，上传rootfs，返回第一步

交付件目标和标准

user
	cmd create-rootfs can use like this
	- internal run cmd virt-build can use like this
	- support daily build iso
	- extract to rootfs

develop

	virt-build support openEuler
	- means upstream support

output:
	- nfsroot dir
	- initramfs .cgz file (all in memory)

### 方案(iso->qcow2->rootfs)

    一、在linux上将iso转换为qcow2的方法有以下几种：

- 使用**qemu-img**命令，这是QEMU的一个工具，可以对镜像文件进行创建、转换、检查等操作。例如，如果您想将ubuntu-20.04.3-desktop-amd64.iso转换为ubuntu.qcow2，您可以使用以下命令：**无效，qemu-img不能直接转换iso**
  qemu不能直接将iso转化成qcow2，但是使用iso创建虚机后会产生qcow2/raw作为虚机的硬盘，因此，可以创建一个qcow2/raw的硬盘，然后再这个硬盘上创建虚拟机，安装完系统后，关闭虚拟机，将写入了系统的qcow2/raw文件压缩导出，即可完成需要的转换。
    1.创建qcow2
  ```
  qemu-img create test2.qcow2 -f qcow2 100G
  ```
  2.创建虚拟机
   使用virt-manager创建虚拟机，过程不做概述。
   3.压缩导出
KVM虚拟机的模版导出，通常都是直接用qemu-img命令可以将默认的raw格式或者qcow2格式的磁盘文件压缩后导出，指令如下：
  ```
  # 将默认raw格式的磁盘，简单压缩转换成qcow2格式
  qemu-img convert -c -f raw -O qcow2 test1.raw test1.qcow2
  ```
  这里的-f参数指定了源文件的格式，-O参数指定了目标文件的格式。您可以使用qemu-img info命令来查看镜像文件的信息。

- 使用**virt-install**命令，这是一个用于创建和安装虚拟机的工具，它可以使用iso文件作为安装媒介，并输出qcow2格式的镜像文件。例如，如果您想使用ubuntu-20.04.3-desktop-amd64.iso创建一个名为ubuntu的虚拟机，并输出ubuntu.qcow2，您可以使用以下命令²：
  ```bash
  virt-install --name ubuntu --ram 2048 --disk path=ubuntu.qcow2,size=10,format=qcow2 --cdrom ubuntu-20.04.3-desktop-amd64.iso --graphics vnc
  ```
  这里的--name参数指定了虚拟机的名称，--ram参数指定了内存大小，--disk参数指定了磁盘路径、大小和格式，--cdrom参数指定了iso文件路径，--graphics参数指定了图形界面类型。您可以使用virsh list --all命令来查看虚拟机的状态²。

- 使用**virt-builder**命令，这是一个用于快速创建虚拟机镜像的工具，它可以从现有的镜像模板中复制和定制镜像文件。例如，如果您想从ubuntu-20.04模板创建一个名为ubuntu.qcow2的镜像文件，并修改一些设置，您可以使用以下命令：
  ```bash
  virt-builder ubuntu-20.04 --output ubuntu.qcow2 --format qcow2 --root-password password:123456 --hostname ubuntu --update
  ```
  这里的--output参数指定了输出文件路径和格式，--root-password参数指定了根用户密码，--hostname参数指定了主机名，--update参数指定了更新系统。您可以使用virt-builder -l命令来查看可用的镜像模板。

    二、不同类型的rootfs包括：

Initramfs：这种类型的rootfs完全运行在内存中。通常在启动过程的早期阶段使用，用于加载必要的模块和驱动程序，然后切换到实际的根文件系统。

NFSroot：在这种类型中，根文件系统位于通过网络文件系统（NFS）协议访问的远程服务器上。系统在启动过程中通过网络挂载根文件系统。

本地LVM中的rootfs：在这种情况下，根文件系统存储在逻辑卷管理器（LVM）卷上。LVM允许通过创建跨多个物理磁盘的逻辑卷来灵活管理磁盘空间。

本地磁盘分区中的rootfs：在这种情况下，根文件系统位于系统的本地磁盘分区上。这是在物理机上进行传统安装的常见方法。

根据其来源，rootfs类型也可以进行分类：

直接安装：这指的是直接在硬件机器上安装根文件系统。可以通过各种方法实现，例如使用kickstart文件进行PXE（Preboot Execution Environment）引导，自动化安装过程。

虚拟机（VM）镜像：可以使用虚拟化技术（如KVM、VirtualBox等）创建一个虚拟机，并将QCOW2镜像文件作为虚拟机的硬盘，然后启动虚拟机并将其转换为rootfs。这种方式需要额外的虚拟化环境的支持和配置。

Docker：Docker允许创建轻量级容器，其中包含应用程序及其依赖项以及最小的根文件系统。在这种情况下，根文件系统是特定于Docker容器的，并可以从Dockerfile构建或从现有的Docker镜像中提取。

为了创建和管理根文件系统，提供了各种工具和框架，例如：

virt-builder：用于构建VM镜像并从中提取根文件系统的工具。通常在libvirt系列的虚拟化工具中使用。

diskimage-builder：diskimage-builder是一个功能强大的工具，用于构建定制的根文件系统镜像，以用于OpenStack环境中的虚拟机实例。它提供了一组元素（elements），这些元素是可插拔的组件，用于定制镜像的不同方面。这些元素包括软件包安装、配置文件修改、用户添加等，可以根据需要进行组合和定制。
diskimage-builder的工作流程如下：
- 定义一个元素集合，用于构建根文件系统镜像。
- 定义元数据文件，指定要构建的镜像类型、大小等信息。
- 运行diskimage-builder命令，根据元素集合和元数据文件构建镜像。
- 构建完成后，可以将生成的镜像上传到OpenStack环境中使用。

packer：一个从单一的模板文件来创建多平台一致性镜像的轻量级开源工具，它能够运行在常用的主流操作系统如Windows、Linux和Mac os上，能够高效的并行创建多平台例如AWS、Azure和Alicloud的镜像，它的目的并不是取代Puppet/Chef等配置管理工具，实际上，当制作镜像的时候，Packer可以使用Chef或者Puppet等工具来安装镜像所需要的软件。

oz（已过时）：以前用于创建VM镜像的工具。已被diskimage-builder和packer等其他工具取代。

veewee（已过时）：用于创建虚拟化的Vagrant镜像的工具。它不再得到积极维护，并已被其他工具取代。


### 方式对比

   一、iso->qcow2

使用qemu-img命令将ISO转换为QCOW2的优缺点：
- 优点：
  - 简单易用：qemu-img是一个简单易用的命令行工具，可以快速将硬盘映像格式转换为QCOW2格式。
  - 跨平台支持：qemu-img是跨平台的工具，可以在多种操作系统上运行，包括Linux、Windows和MacOS等。
  - 高效性能：qemu-img能够以高效的方式进行转换，可以快速创建QCOW2镜像文件。
- 缺点：
  - 仅限于转换：qemu-img只能用于硬盘映像格式到QCOW2的简单转换，不能进行更复杂的定制和配置。(此项目中qemu-img无法直接将iso->qcow2)
  - 缺乏高级功能：qemu-img缺乏一些高级功能，如自定义配置、添加驱动程序或工具等。

使用virt-install命令将ISO转换为QCOW2的优缺点：
- 优点：
  - 支持自定义虚拟机配置：virt-install命令允许用户指定虚拟机的各种配置参数，如虚拟硬件规格、网络设置、存储配置等。
  - 支持交互式安装：virt-install命令可以与用户进行交互，以便在安装过程中提供必要的信息和确认。
  - 支持多种安装源：virt-install命令可以从本地ISO文件、网络上的ISO文件或HTTP/FTP服务器上的ISO文件进行安装。
- 缺点：
  - 安装过程相对复杂：使用virt-install命令进行安装需要用户手动指定各种配置参数，对于没有经验的用户来说可能会比较困难。
  - 不支持自动化：virt-install命令通常需要用户手动输入安装过程中需要的信息，无法实现完全的自动化安装。
  - 需要额外的操作：使用virt-install命令进行安装需要用户提前准备好虚拟机的硬盘镜像文件，而不是直接从ISO文件中创建。

使用virt-builder命令将ISO转换为QCOW2的优缺点：
- 优点：
  - 简化安装过程：virt-builder命令可以自动从ISO文件中创建虚拟机的硬盘镜像文件，并自动安装操作系统和必要的软件包。
  - 支持自动化：virt-builder命令可以通过命令行参数或脚本进行自动化操作，无需用户交互，适合批量创建虚拟机。
  - 支持多种操作系统：virt-builder命令支持多种操作系统的自动安装，包括常见的Linux发行版和Windows等。
- 缺点：
  - 不支持自定义配置：virt-builder命令的安装过程是自动化的，无法手动指定虚拟机的具体配置参数，如硬件规格、网络设置等。
  - 依赖网络连接：virt-builder命令需要连接到网络上的镜像仓库来下载安装所需的软件包，如果网络不稳定或无法连接，则无法完成安装。

  二、qcow2->rootfs

直接安装：
- 优点：
  - 直接安装操作系统到物理机或虚拟机，不需要额外的中间步骤。
  - 可以根据具体需求进行自定义配置和优化，满足特定的应用需求。
  - 可以使用各种工具和方法进行自动化安装，提高部署效率。
- 缺点：
  - 需要手动进行安装和配置，比较繁琐和耗时。
  - 需要手动安装和配置软件包和依赖。
  - 需要占用大量的存储空间。
虚拟机镜像：
- 优点：
  - 可以使用虚拟化技术创建一个虚拟机镜像，将其转换为rootfs。
  - 可以在不同的虚拟化平台上使用，具有良好的可移植性。
  - 可以使用虚拟机模板进行快速部署。
- 缺点：
  - 创建和管理虚拟机镜像需要额外的工作和资源。
  - 镜像文件较大，占用存储空间较多。

Docker：
- 优点：
  - 使用Docker容器可以轻量化地打包和分发应用程序和其依赖
  - 可以快速部署和启动容器，具有高度的可移植性和可扩展性
  - 可以使用Docker镜像仓库进行镜像的管理和共享。
- 缺点：
  - 需要额外学习和了解Docker的概念和技术。
  - Docker容器化的应用程序只能运行在支持Docker的环境中。
  - 不适用于所有类型的应用程序，特别是需要底层硬件访问的应用程序。

diskimage-builder：
- 优点：
  - 支持多种操作系统，包括 CentOS、Debian、Ubuntu、Fedora、openSUSE 等。
  - 可以使用diskimage-builder工具自动化构建rootfs镜像。
  - 可以生成多种格式的镜像文件，如 qcow2、raw、vhd 等。
  - 可以通过配置文件来管理构建过程，方便维护和管理。
- 缺点：
  - 需要学习和掌握diskimage-builder工具的使用。
  - 对于一些特殊需求的支持可能不够完善。
  - 依赖于一些其他工具和组件，如Docker、QEMU等。这可能增加了配置和安装的复杂性。

packer：
- 优点：
  - 在各个不同的环境之间实现最大程度的一致性，减少环境差异导致的生产、测试效率下降。
  - packer工具支持多种虚拟化平台和云平台，具有很好的可移植性。
  - 改变或者重建系统时非常快，是敏捷开发和DevOps中必不可少的一步。
- 缺点：
   - 打包速度相对较慢，特别是在使用大型镜像时。
   - 文档不够完善，可能需要查找其他资源来解决问题。
   - 某些功能需要手动配置，不够智能化。


### 方案选择


步骤一：安装依赖软件包
安装libguestfs和virt-install软件包，版本计划参考openEuler 2203-LTS的libguestfs-1.40.2-28。

步骤二：安装virt-builder源码
安装libguestfs源码包（builder包含在其中），具体修改builder/template/目录下make-template.ml。

步骤三：修改make-template.ml文件
打开make-template.ml文件，进行适配和修改。
修改代码，添加openeuler的模板，例如：let os = OpenEuler "22.03-LTS"。
根据操作系统要求，选择磁盘大小，使用get_virtual_size_gb函数获取适当的虚拟磁盘大小（virtual_size_gb）。
生成kickstart文件（ks），使用make_kickstart函数生成适当的kickstart文件。
根据操作系统要求，找到引导介质（boot_media），使用make_boot_media函数获取适当的引导介质。
为libvirt域创建临时名称（tmpname），生成一个随机的临时名称。
创建最终输出文件名（output），根据操作系统和架构生成输出文件名。

步骤四：查看builder目录下Makefile文件，并修改Makefile.am
打开Makefile，观察发现生成virt-builder-repository命令
仿照$(REPOSITORY_SOURCES_ML) 
编写$(TEMPLATE_SOURCES_ML)
返回libguestfs-1.40.2目录执行：automake，生成Makefile.in
并且执行：make，生成Makefile文件及virt-builder-template命令

```
[root@localhost libguestfs-1.40.2]# make
fatal: not a git repository (or any parent up to mount point /)
Stopping at filesystem boundary (GIT_DISCOVERY_ACROSS_FILESYSTEM not set).
 cd . && /bin/sh ./config.status Makefile
config.status: creating Makefile
fatal: not a git repository (or any parent up to mount point /)
Stopping at filesystem boundary (GIT_DISCOVERY_ACROSS_FILESYSTEM not set).
make  all-recursive
make[1]: Entering directory '/sdb/libguestfs-1.40.2'
Making all in common/mlstdutils
make[2]: Entering directory '/sdb/libguestfs-1.40.2/common/mlstdutils'
 cd ../.. && /bin/sh ./config.status common/mlstdutils/Makefile depfiles
config.status: creating common/mlstdutils/Makefile
config.status: executing depfiles commands
make[2]: Nothing to be done for 'all'.
make[2]: Leaving directory '/sdb/libguestfs-1.40.2/common/mlstdutils'
Making all in generator
make[2]: Entering directory '/sdb/libguestfs-1.40.2/generator'
 cd .. && /bin/sh ./config.status generator/Makefile
config.status: creating generator/Makefile
make[2]: Nothing to be done for 'all'.
make[2]: Leaving directory '/sdb/libguestfs-1.40.2/generator'
Making all in tests/qemu
make[2]: Entering directory '/sdb/libguestfs-1.40.2/tests/qemu'
 cd ../.. && /bin/sh ./config.status tests/qemu/Makefile
config.status: creating tests/qemu/Makefile
make[2]: Nothing to be done for 'all'.

```
步骤五：生成镜像
在builder目录下执行：./virt-builder-template openeuler 22.03-LTS

```
[root@localhost builder]# ./virt-builder-template openeuler 22.03-LTS
'virt-install' \
    '--transient' \
    '--name=tmp-h3rjyqc9' \
    '--ram=2048' \
    '--arch=x86_64' \
    '--cpu=host' \
    '--vcpus=4' \
    '--os-variant=voidlinux' \
    '--initrd-inject=openeuler-22.03-LTS.ks' \
    '--extra-args=inst.ks=file:/openeuler-22.03-LTS.ks  console=tty0 console=ttyS0,115200 rd_NO_PLYMOUTH' \
    '--disk=/sdb/libguestfs-1.40.2/builder/tmp-h3rjyqc9.img,size=6,format=raw' \
    '--location=/sdb/libguestfs-1.40.2/builder//openEuler-22.03-LTS-x86_64-dvd.iso' \
    '--serial=pty' \
    '--nographics'



WARNING  KVM acceleration not available, using 'qemu'
WARNING  No --console device added, you likely will not see text install output from the guest.

Starting install...
Retrieving file vmlinuz...                                                                           |  10 MB  00:00:00
Retrieving file initrd.img...                                                                        |  65 MB  00:00:00
Allocating 'tmp-h3rjyqc9.img'                                                                        | 6.0 GB  00:00:00
Connected to domain tmp-h3rjyqc9
Escape character is ^] (Ctrl + ])
[    0.000000][    T0] Linux version 5.10.0-60.18.0.50.oe2203.x86_64 (abuild@ecs-obsworker-209) (gcc_old (GCC) 10.3.1, GNU ld (GNU Binutils) 2.37) #1 SMP Wed Mar 30 03:12:24 UTC 2022
[    0.000000][    T0] Command line: inst.ks=file:/openeuler-22.03-LTS.ks  console=tty0 console=ttyS0,115200 rd_NO_PLYMOUTH
[    0.000000][    T0] x86/fpu: Supporting XSAVE feature 0x001: 'x87 floating point registers'
[    0.000000][    T0] x86/fpu: Supporting XSAVE feature 0x002: 'SSE registers'
[    0.000000][    T0] x86/fpu: Supporting XSAVE feature 0x008: 'MPX bounds registers'
[    0.000000][    T0] x86/fpu: Supporting XSAVE feature 0x010: 'MPX CSR'
[    0.000000][    T0] x86/fpu: Supporting XSAVE feature 0x200: 'Protection Keys User registers'
[    0.000000][    T0] x86/fpu: xstate_offset[3]:  960, xstate_sizes[3]:   64
[    0.000000][    T0] x86/fpu: xstate_offset[4]: 1024, xstate_sizes[4]:   64
[    0.000000][    T0] x86/fpu: xstate_offset[9]: 2688, xstate_sizes[9]:    8
[    0.000000][    T0] x86/fpu: Enabled xstate features 0x21b, context size is 2696 bytes, using 'standard' format.
[    0.000000][    T0] BIOS-provided physical RAM map:
[    0.000000][    T0] BIOS-e820: [mem 0x0000000000000000-0x000000000009fbff] usable
[    0.000000][    T0] BIOS-e820: [mem 0x000000000009fc00-0x000000000009ffff] reserved
[    0.000000][    T0] BIOS-e820: [mem 0x00000000000f0000-0x00000000000fffff] reserved
[    0.000000][    T0] BIOS-e820: [mem 0x0000000000100000-0x000000007ffdbfff] usable
[    0.000000][    T0] BIOS-e820: [mem 0x000000007ffdc000-0x000000007fffffff] reserved
[    0.000000][    T0] BIOS-e820: [mem 0x00000000b0000000-0x00000000bfffffff] reserved
[    0.000000][    T0] BIOS-e820: [mem 0x00000000fed1c000-0x00000000fed1ffff] reserved
[    0.000000][    T0] BIOS-e820: [mem 0x00000000fffc0000-0x00000000ffffffff] reserved
[    0.000000][    T0] NX (Execute Disable) protection: active

```
步骤六：解压镜像

```
[root@localhost builder]# xz -d openeuler-22.03-LTS.xz

```

步骤七：提取内核
在命令行中使用以下命令提取镜像内核：virt-builder --get-kernel

```
virt-builder --get-kernel openeuler-22.03-LTS
download: /boot/vmlinuz-5.10.0-60.18.0.50.oe2203.x86_64 -> ./vmlinuz-5.10.0-60.18.0.50.oe2203.x86_64
download: /boot/initramfs-5.10.0-60.18.0.50.oe2203.x86_64.img -> ./initramfs-5.10.0-60.18.0.50.oe2203.x86_64.img

```
步骤八：提取rootfs
在命令行执行virt-tar-out -a < > 提取rootfs

```
[root@localhost builder]# virt-tar-out -a openeuler-22.03-LTS / rootfs.tar

```
步骤九：自动化生成
通过编写shell脚本，使用户在命令行通过一条命令实现iso->rootfs
  ```
[root@localhost ~]# ./iso2rootfs -h
Usage: iso2rootfs -d <Dist> -r <Release> [-p] [/path/virt-x-dir/]
Example: iso2rootfs -d openeuler -r 22.03-lts
  ```
  ```
Domain creation completed.
Name       Type        VFS      Label  MBR  Size  Parent
/dev/sda1  filesystem  unknown  -      -    1.0M  -
/dev/sda2  filesystem  ext4     -      -    1.0G  -
/dev/sda3  filesystem  swap     -      -    615M  -
/dev/sda4  filesystem  ext4     -      -    4.4G  -
/dev/sda1  partition   -        -      -    1.0M  /dev/sda
/dev/sda2  partition   -        -      -    1.0G  /dev/sda
/dev/sda3  partition   -        -      -    615M  /dev/sda
/dev/sda4  partition   -        -      -    4.4G  /dev/sda
/dev/sda   device      -        -      -    6.0G  -
Sysprepping ...
Sparsifying ...
Compressing ...
Template completed: openeuler-20.03-LTS.xz
openeuler-20.03-LTS.index-fragment validated OK
Index fragment created: openeuler-20.03-LTS.index-fragment
Finished successfully.
download: /boot/vmlinuz-4.19.90-2003.4.0.0036.oe1.x86_64 -> ./vmlinuz-4.19.90-2003.4.0.0036.oe1.x86_64
download: /boot/initramfs-4.19.90-2003.4.0.0036.oe1.x86_64.img -> ./initramfs-4.19.90-2003.4.0.0036.oe1.x86_64.img
  ```

### 方案验证

```
[root@localhost create-rootfs]# ./verify_install -l /sdb/libguestfs-1.40.2/builder/openeuler-22.03-LTS
```
```
[root@localhost create-rootfs]# cat verify_install
#!/bin/bash

#!/bin/bash

while [ -n "$1" ]
    do
        case "$1" in
            -l|--location)
                echo "param location"
                loc="$2"
                echo $loc
                shift 2
                ;;
            -h|--help)
                usage
                return 0
                ;;
            --)
                shift
                break
                ;;
            *)
                return 1
                ;;
            esac
    done


/usr/libexec/qemu-kvm \
        -m 2048 \
        -smp 2 \
        -boot cd \
        -hda $loc \
        -serial stdio

```

 - kernel的验证

```
[root@localhost builder]# file vmlinuz-5.10.0-60.18.0.50.oe2203.x86_64
vmlinuz-5.10.0-60.18.0.50.oe2203.x86_64: Linux kernel x86 boot executable bzImage, version 5.10.0-60.18.0.50.oe2203.x86_64 (abuild@ecs-obsworker-209) #1 SMP Wed Mar 30 03:12:24 UTC 2022, RO-rootFS, swap_dev 0X9, Normal VGA

```

 - rootfs.tar的验证

```
[root@localhost rootfs]# tar -xvf rootfs.tar

./
./etc/
./etc/rc2.d
./etc/modules-load.d/
./etc/nftables/
./etc/nftables/bridge-filter.nft
./etc/nftables/ipv4-nat.nft
./etc/nftables/inet-nat.nft
./etc/nftables/ipv6-nat.nft
./etc/nftables/ipv4-raw.nft
./etc/nftables/ipv6-filter.nft
./etc/nftables/ipv6-mangle.nft
./etc/nftables/ipv4-filter.nft
./etc/nftables/inet-filter.nft
./etc/nftables/all-in-one.nft
./etc/nftables/ipv6-raw.nft
./etc/nftables/ipv4-mangle.nft
./etc/nftables/arp-filter.nft
./etc/nftables/osf/
./etc/nftables/osf/pf.os
./etc/nftables/netdev-ingress.nft
./etc/init.d

```
```
[root@localhost rootfs]# ls -lh
total 1.7G
dr-xr-xr-x  2 root root 4.0K Mar 13  2022 afs
lrwxrwxrwx  1 root root    7 Mar 13  2022 bin -> usr/bin
dr-xr-xr-x  7 root root 4.0K Jul 25 15:41 boot
drwxr-xr-x  2 root root 4.0K Jul 25 14:55 dev
drwxr-xr-x 84 root root 4.0K Jul 25 16:08 etc
drwxr-xr-x  2 root root 4.0K Mar 13  2022 home
lrwxrwxrwx  1 root root    7 Mar 13  2022 lib -> usr/lib
lrwxrwxrwx  1 root root    9 Mar 13  2022 lib64 -> usr/lib64
drwx------  2 root root 4.0K Jul 25 14:54 lost+found
drwxr-xr-x  2 root root 4.0K Mar 13  2022 media
drwxr-xr-x  2 root root 4.0K Mar 13  2022 mnt
drwxr-xr-x  2 root root 4.0K Mar 13  2022 opt
drwxr-xr-x  2 root root 4.0K Jul 25 14:55 proc
dr-xr-x---  2 root root 4.0K Jul 25 16:08 root
-rw-r--r--  1 root root 1.7G Jul 25 16:36 rootfs.tar
drwxr-xr-x  2 root root 4.0K Jul 25 14:55 run
lrwxrwxrwx  1 root root    8 Mar 13  2022 sbin -> usr/sbin
drwxr-xr-x  2 root root 4.0K Mar 13  2022 srv
drwxr-xr-x  2 root root 4.0K Jul 25 14:55 sys
drwxrwxrwt  2 root root 4.0K Jul 25 16:08 tmp
drwxr-xr-x 12 root root 4.0K Jul 25 15:01 usr
drwxr-xr-x 19 root root 4.0K Jul 25 15:30 var

```
### 个人理解与问题

 - 理解：本项目为通过命令行指令一次性实现操作系统的iso->rootfs。
     初期编写ks文件由make-template命令实现iso镜像的生成，通过virt-builder --get-kernel和virt-tar-out -a < > 提取内核与rootfs；
     中期对builder/template/目录下make-template.ml进行适配和修改，查看builder目录下Makefile文件，并修改Makefile.am打开Makefile，观察发现生成virt-builder-repository命令，仿照$(REPOSITORY_SOURCES_ML) 编写$(TEMPLATE_SOURCES_ML)生成Makefile文件及virt-builder-template命令；
   后期为实现全自动化编写shell脚本，使用户在命令行通过一条命令实现iso->rootfs。


 - 存在问题：由于网络原因，除openeuler的操作系统之外，centos ， debian，ubuntu, fedora操作系统无法通过脚本一次性实现由网络获取iSO->rootfs。

### 后续想法

 - 由于版本计划参考为openEuler 2203-LTS的libguestfs-1.40.2-28，最新的openEuler 23.03版本的libguestfs版本为1.49.5。在最新版本的libguestfs中移除了virt-builder命令，导致该rootfs制作方案无法在新版本实现。
   经过观察发现virt-install命令仍存在，后续如需要适配最新版本的libguestfs，可由代码生成ks文件，然后通过virt-install命令创建镜像文件。

