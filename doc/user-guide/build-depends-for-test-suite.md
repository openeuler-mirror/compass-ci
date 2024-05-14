# 构建测试用例依赖包介绍

[toc]

## 简介

依赖包是lkp-tests/tests/中测试用例运行时需要的cgz文件(cgz既cpio.gz，是gzip压缩后的cpio归档文件，linux kernel initrd标准格式)，一类是通过cci-depends生成，该用例通过包管理器下载软件包进行封装成cgz文件，一类是通过cci-makepkg生成，该用例利用makepkg脚本进行源码编译后的二进制文件封装成cgz文件。依赖包可以减少测试用例运行时安装依赖时的网络操作或编译耗时。

### 强相关文件目录结构

```shell
cci-depends:
lkp-tests/tests/cci-depends             # 利用发行版包管理器如yum/apt/packman下载封装成cgz包，包中含有如rpm包、deb包、tar包（archlinux）
lkp-tests/jobs/cci-depends.yaml         # cci-depends用例提交yaml
cci-makepkg:
lkp-tests/tests/cci-makepkg             # 利用makepkg编译源码构建依赖包，内容为二进制文件
lkp-tests/jobs/cci-makepkg.yaml         # cci-makepkg用例提交yaml
lkp-tests/sbin/makepkg                  # makepkg脚本，cci-makepkg构建源码包时调用处理PKGBUILD
lkp-tests/pkg/${benchmark}/             # 保存makepkg脚本使用的PKGBUILD文件
lkp-tests/installer/${OS}               # 保存以各发行版命名的简单的安装软件包的脚本合集，旨在运行cci-makepkg时为待编译的软件包安装依赖
lkp-tests公共调用：
lkp-tests/depends/${benchmark}          # 保存以各测试用例命名的文件，内容为测试用例运行时依赖包列表，默认为debian包名
lkp-tests/distro/${OS}                  # 各发行版包含打包需要的函数
lkp-tests/distro/adaptation/${os}       # cci-depends各发行版依赖关系键值对文件，内容默认为debian到其他系统的映射关系
lkp-tests/lib/bootstrap.sh              # 安装cgz包函数位置
lkp-tests/bin/lkp-setup-rootfs          # 下载测试用例cgz文件函数及安装解压安装cgz包
compass-ci：
compass-ci/container/srv-http           # 提供下载cgz包服务
compass-ci/container/result-webdav      # nginx负责为上传的cgz包创建软链接
compass-ci/src/lib/job.cr               # 调度器相关代码，负责查找依赖包组装job
```

## cci-depends执行流程

- 用户提交任务后，调度器会查找待构建包的相关依赖包，并将其添加到job initrd_deps字段里

  - ```
    initrd_deps:
    - http://172.168.131.113:8800/initrd/deps/initramfs/openeuler/aarch64/20.03-LTS-SP2-iso/lkp/lkp_20211116.cgz
    - http://172.168.131.113:8800/initrd/deps/initramfs/openeuler/aarch64/20.03-LTS-SP2-iso/iostat/iostat_20211222.cgz
    - http://172.168.131.113:8800/initrd/deps/initramfs/openeuler/aarch64/20.03-LTS-SP2-iso/perf-stat/perf-stat_20211222.cgz
    - http://172.168.131.113:8800/initrd/deps/initramfs/openeuler/aarch64/20.03-LTS-SP2-iso/perf-profile/perf-profile_20211222.cgz
    - http://172.168.131.113:8800/initrd/deps/initramfs/openeuler/aarch64/20.03-LTS-SP2-iso/netperf/netperf_20211118.cgz
    ```


- 当lkp-tests在测试机中启动时，调用lkp-tests/bin/lkp-setup-rootfs下载job相关依赖包并安装

- 执行cci-depends

  - 加载lkp-tests/distro/${OS}各发行版打包需要的函数
  - 根据lkp-tests/depends/${benchmark}及lkp-tests/distro/adaptation/${OS}生成映射后包列表
  	
  	>例：netperf在openeuler下包映射处理

  	```shell
  	cat lkp-tests/depends/netperf
  	libsctp1
  	lksctp-tools
  	ethtool
  	```
  	```shell
  	cat lkp-tests/distro/adaptation/openeuler
  	libsctp1: lksctp-tools
  	```

  	```
  	经过处理后得到一份${packages}列表：
  	lksctp-tools
  	lksctp-tools
  	ethtool
  	```

- 测试机下载${packages}并制作cgz文件

- 测试机向服务器容器result-webdav发送请求上传cgz文件，result-webdav在服务器上创建软链接

## cc-makepkg执行流程

- 用户提交任务后，调度器会查找待构建包的相关依赖包，并将其添加到job initrd_pkgs字段里

  - ```
    initrd_pkgs:
    - http://172.168.131.113:8800/initrd/pkg/initramfs/openeuler/aarch64/20.03-LTS-SP2-iso/netperf/2.7-0.cgz
    ```

- 当lkp-tests在测试机中启动时，下载job相关依赖包并安装

- 执行cci-makepkg
  - 加载lkp-tests/distro/${OS}各发行版打包需要的函数，通过加载lkp-tests/lib/install.sh调用各发行版安装软件包的脚本
  - 根据lkp-tests/depends/${benchmark}及lkp-tests/distro/adaptation/${OS}生成映射后包列表
  - 根据映射关系安装${benchmark}开发包
  - 通过lkp-tests/sbin/makepkg处理${benchmark}的PKGBUILD，编译并制作cgz文件
  - 测试机向服务器容器result-webdav发送请求上传cgz，result-webdav在服务器上创建软链接

### PKGBUILD编写

> 参考：[PKGBUILD - ArchWiki (archlinux.org)](https://wiki.archlinux.org/title/PKGBUILD)
>
> 参考：lkp-tests/pkg/下存在大量可参考的PKGBUILD

## 用户使用场景

### 依赖包任务常见场景

> 需求：用户想在容器openeuler:20.03-LTS-SP1上进行netperf测试，openeuler:20.03-LTS-SP1上没有netperf软件包
>
> 依赖包使用场景：利用cci-makepkg编译netperf，将二进制文件封装成cgz以完成测试
>
> 需求：用户想在容器openeuler:20.03-LTS-SP1上进行iperf测试，openeuler:20.03-LTS-SP1上存在iperf软件包
>
> 依赖包使用场景：利用cci-depends下载iperf及其依赖，封装成cgz文件，测试机下载cgz安装iperf软件包以完成测试

### 确认iperf依赖

```
cat lkp-tests/distro/depends/iperf
iperf3
```

openeuler:20.03-LTS-SP1 确认iperf包

```
$ yum search iperf3.aarch64
iperf3.aarch64 : TCP,UDP,and SCTP network bandwidth measurement tool
```

### 确认netperf依赖

通过cci-makepkg编译出netperf后，进行netperf测试时缺少的依赖可继续通过cci-depends/cci-makepkg补充

#### 提交任务

```shell
cci-depends: 
$ submit cci-depends.yaml cci-depends.benchmark=iperf docker_image=openeuler:20.03-LTS-SP1
cci-makepkg: 
$ submit cci-makepkg.yaml cci-makepkg.benchmark=netperf docker_image=openeuler:20.03-LTS-SP1
```

> 参考： [submit 命令详解]([doc/job/submit/submit-job.zh.md · Fengguang/compass-ci - 码云 - 开源中国 (gitee.com)](https://gitee.com/openeuler/compass-ci/blob/master/doc/job/submit/submit-job.zh.md))

#### 查看输出

- cci-depends结果目录及文件内容：

> 除非软件源修改，依赖增加或删除，不同日期生成的cgz一般没有什么不同

```
/srv/initrd/deps/container/openeuler/aarch64/20.03-LTS-SP1/iperf
rw-rw-r--. 1 lkp lkp 80K 2021-09-09 01:44 iperf_20210909.cgz
-rw-rw-r--. 1 lkp lkp 80K 2021-09-10 16:46 iperf_20210910.cgz
lrwxrwxrwx. 1 lkp lkp  18 2021-09-10 16:46 iperf.cgz -> iperf_20210910.cgz
```

```shell
opt/rpms
opt/rpms/iperf3-3.6-5.oe1.aarch64.rpm
opt/rpms/iperf3-help-3.6-5.oe1.noarch.rpm
```

- cci-makepkg结果目录及文件内容

> 除非修改PKGBUILD导致版本号更改，否则总是指向同一个版本

```
/srv/initrd/pkg/container/openeuler/aarch64/20.03-LTS-SP1/netperf/
-rw-rw-r--. 1 lkp lkp 260K 2021-09-09 02:09 2.7-0.cgz
lrwxrwxrwx. 1 lkp lkp    9 2021-09-09 02:09 latest.cgz -> 2.7-0.cgz
```

```shell
.
.PKGINFO
lkp
lkp/benchmarks
lkp/benchmarks/netperf
lkp/benchmarks/netperf/share
lkp/benchmarks/netperf/share/man
lkp/benchmarks/netperf/share/man/man1
lkp/benchmarks/netperf/share/man/man1/netserver.1
lkp/benchmarks/netperf/share/man/man1/netperf.1
lkp/benchmarks/netperf/share/info
lkp/benchmarks/netperf/share/info/dir
lkp/benchmarks/netperf/share/info/netperf.info
lkp/benchmarks/netperf/bin
lkp/benchmarks/netperf/bin/netserver
lkp/benchmarks/netperf/bin/netperf
```

## TODO
> 自动提交cci-depends, cci-makepkg任务，用户仅添加测试用例需要的依赖包名称及映射或PKGBUILD等相关文件即可
