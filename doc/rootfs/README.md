[TOC]

1 序
====

Compass-CI的使用是通过[提交job](../job/submit/submit-job.zh.md)来进行的。

你提交的job对应着有其测试脚本，测试脚本的运行是要在某一个执行机（`testbox`）上，在某一个系统（`os`, `os_arch`, `os_version`）上运行的。

而对于compass-ci而言，需要统一调度，如何为每一个job提供一个相同的，干净的初始环境呢？

目前，我们有以下几种方式：

1.1 docker image as 根系统
--------------------------

> 前提：
> 1. 已经通过将指定版本的docker image存储到了本地的${DOCKER_REGISTRY_HOST}服务器上；
> 2. 所有testbox均可以通过`docker pull ${DOCKER_REGISTRY_HOST}:${DOCKER_REGISTRY_PORT}/$docker_image`获取到镜像。
> 3. ${DOCKER_REGISTRY_HOST}与${DOCKER_REGISTRY_PORT}的值可以在Compass-CI集群主节点的/etc/compass-ci/service/service-env.yaml中看到。

此种方式，每一个testbox(docker容器)在执行job之前，都会从本地的docker仓库中pull一个镜像。
这样，我们就保证了每一个job都拥有一个相同的，干净的初始环境。

> 用户如果想选用这种job运行系统是以cifs/nfs挂载的方式，需要指定os_mount=container。
> demo:待补充

1.2 cifs/nfs挂载 as 根系统
--------------------------

> 前提：
> 1. 已经通过将指定版本的iso安装到物理机/虚拟机的硬盘成功，并且将硬盘里的文件系统拷贝出来，放到Compass-CI集群的${OS_HTTP_HOST}服务器上的指定格式的目录下;
> 2. 所有testbox均可以通过http && cifs && nfs协议访问到${OS_HTTP_HOST}:${OS_HTTP_PORT}/os/${os}/${os_arch}/${os_version}这个文件系统的内容;
> 3. ${OS_HTTP_HOST}与${OS_HTTP_PORT}的值可以在Compass-CI集群主节点的/etc/compass-ci/service/service-env.yaml中看到。

此种方式，每一个testbox在执行job的时候，job运行所在的文件系统，是cifsroot/nfsroot，也就是说，这种类型的job，它的根目录，是挂载的远程cifs/nfs服务端的文件系统。

现在让我们来更进一步，Compass-CI为了保证每一个job都拥有一个相同的，干净的初始环境，我们做了以下步骤：
- cifs/nfs服务端提供的，为不同job提供的文件系统，是只允许以只读形式挂载；
- 在testbox挂载cifsroot/nfsroot时（testbox的initramfs阶段），也以只读形式挂载之后，在其上增加一层可读写的overlayfs；

这样，我们就保证了每一个job都拥有一个相同的，干净的初始环境。

> 用户如果想选用这种job运行系统是以cifs/nfs挂载的方式，需要指定os_mount=cifs（或者os_mount=nfs）。
> demo:待补充

1.3 initramfs as 根系统
-----------------------

> 前提：
> 1. 已经通过将指定版本的iso安装到物理机/虚拟机的硬盘成功，并且将硬盘里的文件系统拷贝出来，放到Compass-CI集群的${OS_HTTP_HOST}服务器上的指定格式的目录下;
> 2. 已经基于步骤1 的文件系统，将其制作为内核可识别的inird文件，放到Compass-CI集群的${INITRD_HTTP_HOST}服务器上的指定格式的目录下；
> 3. 所有testbox均可以通过http协议访问到如下内容：
>    - ${OS_HTTP_HOST}:${OS_HTTP_PORT}/os/${os}/${os_arch}/${os_version}/boot/vmlinuz
>    - ${OS_HTTP_HOST}:${OS_HTTP_PORT}/os/${os}/${os_arch}/${os_version}/boot/modules.cgz
>    - ${INITRD_HTTP_HOST}:${INITRD_HTTP_PORT}/initrd/osimage/${os}/${os_arch}/${os_version}/current
>    - ${INITRD_HTTP_HOST}:${INITRD_HTTP_PORT}/initrd/osimage/${os}/${os_arch}/${os_version}/run-ipconfig.cgz
> 4. ${OS_HTTP_HOST}, ${OS_HTTP_PORT}, ${INITRD_HTTP_HOST}, ${INITRD_HTTP_PORT}的值可以在Compass-CI集群主节点的/etc/compass-ci/service/service-env.yaml中看到。

此种方式，每一个testbox在执行job的时候，job运行所在的文件系统，位于内存，也就是说，这种类型的job，他的根目录的所有文件，都是一次性加载到内存中了。

现在让我们来更进一步，Compass-CI为了保证每一个job都拥有一个相同的，干净的初始环境，我们做了以下步骤：
- testbox在initramfs阶段，将Compass-CI服务端的文件系统压缩文件下载下来，解压开来，直接来让job使用。

这样，由于testbox的initramfs阶段是位于内存中的，所以，整个job所使用的文件系统，也是位于内存中的。

另外，由于每个job会在自己的testbox上执行，而每个testbox，会下载服务端的文件系统压缩文件下载下来，这样，我们就保证了每一个job都拥有一个相同的，干净的初始环境。

> 用户如果想选用这种job运行系统是以内存加载initramfs的方式，需要指定os_mount=initramfs。
> demo:待补充

1.4 本地硬盘 as 根系统
----------------------

> 前提：
> 1. 已经通过将指定版本的iso安装到物理机的硬盘成功，并且将硬盘里的文件系统拷贝出来，放到Compass-CI集群的${OS_HTTP_HOST}服务器上的指定格式的目录下;
> 2. 所有testbox均可以通过http && nfs协议访问到${OS_HTTP_HOST}:${OS_HTTP_PORT}/os/${os}/${os_arch}/${os_version}-iso到这个文件系统的内容;
> 3. ${OS_HTTP_HOST}与${OS_HTTP_PORT}的值可以在Compass-CI集群主节点的/etc/compass-ci/service/service-env.yaml中看到。

此种方式，每一个testbox在执行job的时候，job运行所在的文件系统，是硬盘上的一个lv（逻辑卷logic volume）。也就是说，这种类型的job，它的根目录，是本机硬盘上的文件系统。

现在让我们来更进一步，Compass-CI为了保证每一个job都拥有一个相同的，干净的初始环境，我们做了以下步骤：
- 在testbox的initramfs阶段，将Compass-CI集群的${OS_HTTP_HOST}服务器上的${OS_HTTP_HOST}:${OS_HTTP_PORT}/os/${os}/${os_arch}/${os_version}-iso对应目录的文件系统拷贝到本地指定硬盘的指定格式的lv中。
- 使用这个lv启动系统。

这样，我们就保证了每一个job都拥有一个相同的，干净的初始环境。

> 用户如果想选用这种job运行系统是本地硬盘的方式，需要指定os_mount=local。


2 概念解释
==========

2.1 Compass-CI的rootfs是什么？
------------------------------

Compass-CI的rootfs是指存放在服务器端的，有版本的，可以为执行机在执行指定os,os_arch,os_version的job时提供相同的，干净的执行环境的docker镜像/文件/目录。

Compass-CI当前可供测试的执行机类型有：docker, 虚拟机, 物理机。
- 对docker而言，rootfs就是docker registry里面的指定版本的docker image。
- 对虚拟机和物理机而言，rootfs就是在指定版本的iso安装完毕后，将其所有文件（运行时文件除外）拷贝出来，归档到/srv/os或/srv/initrd下版本对应的目录/文件。

2.2 os_mount是什么？
--------------------

Compass-CI的job执行是通过submit命令来触发的，os_mount是submit时候的一个参数，用来指定本次job执行所需os是通过何种方式提供的。

|----------------------------------|-------------------------------------------------------------------------------|
| Compass-CI目前支持的os_mount类型 | 简单说明                                                                      |
|----------------------------------|-------------------------------------------------------------------------------|
| container                        | 对应执行环境为docker                                                          |
| initramfs                        | 内存文件系统，系统所需文件一次性全部加载到内存中                              |
| nfs                              | 内存文件系统，系统所需文件是通过nfs协议mount的，使用到多少文件，加载多少文件  |
| cifs                             | 内存文件系统，系统所需文件是通过cifs协议mount的，使用到多少文件，加载多少文件 |
| local                            | 硬盘文件系统，系统所需文件是位于一个指定名称格式的逻辑卷中                    |
|----------------------------------|-------------------------------------------------------------------------------|

2.3 rootfs与os_mount的关系是什么？
----------------------------------

job通过submit命令来提交到compass-ci调度器；

submit job时候需要指定os_mount，若不指定，默认值如下：
- 若指定本次执行机类型为docker，则os_mount默认为container；
- 若指定本次执行机类型为虚拟机/物理机，则os_mount默认为initramfs；

rootfs需要在sbumit job之前制作好，否则submit job会得到错误返回。

job has many fields, the point of one/some fields .


|--------------|-----------------------------------------------------------------|
| os_mount类型 | 对应的rootfs存储位置                                            |
|--------------|-----------------------------------------------------------------|
| container    | Compass-CI集群的docker registry。image格式：${os}:${os_version} |
| initramfs    | /srv/initrd/osimage/${os}/${os_arch}/${os_version}/current      |
| cifs/nfs     | /srv/os/${os}/${os_arch}/${os_version}                          |
| local        | /srv/os/${os}/${os_arch}/${os_version}-iso                      |
|--------------|-----------------------------------------------------------------|

注：
local与cifs/nfs现阶段的区别如下：
- cifs/nfs所需的rootfs目前是通过安装iso到虚拟机得到的；
- local所需的rootfs目前是通过安装iso到物理机得到的；
- 理论上：
  - 就与手动安装iso到物理机的系统差异而言，安装iso到物理机得到的rootfs，差异是小于安装iso到虚拟机得到的rootfs的；
  - 所以，local能用的rootfs，是可以直接用于cifs/nfs的，而且以后如果安装iso到物理机得到rootfs的方式自动化完毕，那么在磁盘的/srv/os下，是只需要保留安装iso到物理机得到的rootfs的，现阶段local需要的-iso后缀可以去掉，cifs/nfs/local，都使用同一套rootfs。


3 使用指南
==========

[提交job](../job/submit/submit-job.zh.md)
[os_mount](../job/fields/os_mount.md)
如何查看当前compass-ci集群支持的rootfs都有哪些？ # 待补充


4 管理员手册
============

4.1 Compass-CI的rootfs是怎么来的？（原理）
------------------------------------------

### 4.1.1 container

基于指定版本的基础镜像基础，制作docker image，并上传到docker registry中

### 4.1.2 nfs/cifs

- 安装iso到虚拟机的硬盘（qcow2）上；
- 安装完成后，使用硬盘系统再进行一次启动/关机操作；
- 将qcow2中的rootfs拷贝出来； # 可以使用compass-ci/container/qcow2rootfs容器进行拷贝
- 对拷贝出来的rootfs进行一些post配置，即可用于compass-ci。

> 详细post配置见之后的rootfs如何制作部分

### 4.1.3 local

- 安装iso到物理机的硬盘A上；
- 安装完成后，使用硬盘A上的系统再进行一次启动/关机操作；
- 使用非安装iso的硬盘A启动系统（可以使用内存文件系统，也可以使用其他硬盘上的系统），将硬盘A中的rootfs拷贝出来；
- 对拷贝出来的rootfs进行一些post配置，即可用于compass-ci。

> 详细post配置见之后的rootfs如何制作部分

### 4.1.4 initramfs

iniramfs所需的rootfs是一个包含了所有系统必须文件的cgz文件。
所以我们使用cpio将cifs/nfs/local制作出来的rootfs打包制作成cgz文件即可。
假设此rootfs位于B目录，将B目录整体打包。

> 详细打包命令见之后的rootfs如何制作部分


4.2 我已有Compass-CI集群，如何获得rootfs？
------------------------------------------

[我已有Compass-CI集群，如何获得rootfs？](./how-to-get-rootfs/README.md)


4.3 我已有Compass-CI集群，已有rootfs，如何更新？
------------------------------------------------

### 4.3.1 更新os_mount=container的rootfs

根据docker registry里的基线版本启动一个docker container，进行需要的更新后，覆盖提交到docker registry。

### 4.3.2 更新os_mount=cifs/nfs/local的rootfs

根据/srv/os/${os}/${os_arch}/${os_version}这个软链接指向的基线版本目录复制一个新的版本目录，在新版本目录中进行需要的更新后，将软链接指向新的版本。

### 4.3.3 更新os_mount=initramfs的rootfs

将/srv/initrd/osimage/${os}/${os_arch}/${os_version}/current这个软链接指向的基线版本cgz解压到一个临时目录，在临时版本目录中进行需要的更新后，将临时目录重新打包为新的版本，并将软链接指向新的版本。

解压cgz命令参考：
```
unzip_dir="$(date "+%Y%m%d%H%M")-unzip"

mkdir -p $unzip_dir && cd $unzip_dir
zcat < $(realpath /srv/initrd/osimage/${os}/${os_arch}/${os_version}/current) | cpio -idmv
```

制作cgz命令参考：
- 参考之前的手动制作initramfs rootfs步骤


4.4 Compass-CI内部是如何使用rootfs的？
--------------------------------------

[os_mount=container的rootfs是如何使用起来的](./compass-ci-use-rootfs/container.md)

[os_mount=cifs/nfs的rootfs是如何使用起来的](./compass-ci-use-rootfs/cifs-nfs.md)

[os_mount=local的rootfs是如何使用起来的](./compass-ci-use-rootfs/local.md)

[os_mount=initramfs的rootfs是如何使用起来的](./compass-ci-use-rootfs/initramfs.md)
