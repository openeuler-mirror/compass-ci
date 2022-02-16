[toc]

## 在介绍iPXE之前，需要先了解一些预备知识

###  服务器启动的一般流程

#### 1. 上电启动主板上的BIOS或者UEFI BIOS程序

#### 2. BIOS寻找并加载boot loader

计算机寻找被称为引导加载程序的方式非常灵活，比如，

- UEFI -> GPT硬盘分区 -> GRUB2
加载 /boot/efi/EFI/openEuler/grubaa64.efi ；x86_64的机器则是 grubx64.efi 文件

- BIOS -> MBR硬盘分区 -> GRUB2
加载第一块硬盘第一个扇区中的 Stage 1 bootloader，然后再加载 Stage 2 bootloader
stage 2的相关文件在该硬盘分区的 /boot/grub2 目录下。 

- BIOS/UEFI -> PXE -> Download from network
bootloader 文件为"pxelinux.0"

- BIOS/UEFI -> PXE -> iPXE -> Download from network
使用传统 BIOS 启动，iPXE的文件为"undionly.kpxe"；使用UEFI启动，iPXE的文件为"ipxe.efi"

- BIOS -> MBR硬盘分区 -> GRUB2 -> iPXE
使用 BIOS 启动，开机加载硬盘上的 GRUB2，再从GRUB2 去加载硬盘上的 iPXE 的程序文件。

> 需要预先将iPXE的程序文件放到 /boot分区下，并添加到 grub.cfg 的启动项，并设置以 iPXE 的启动项重新启动。

#### 3. BootLoader 引导内核

bootloader 的引导过程，可以参考文档: https://www.kernel.org/doc/html/latest/arm64/booting.html

在常用的 gurb.cfg 中的配置中，使用 GRUB2 的命令，指定 kernel image 和 initial ramdisk 引导内核，进而启动操作系统。
示例如下：
```
	linux	/vmlinuz-4.19.90-btrfs-arm64 root=/dev/mapper/openeuler-root ro rd.lvm.lv=openeuler/root rd.lvm.lv=openeuler/swap  smmu.bypassdev=0x1000:0x17 smmu.bypassdev=0x1000:0x15 crashkernel=1024M,high

	initrd	/initramfs.lkp-4.19.90-btrfs-arm64.img
```

`linux` 命令后面的参数解释，可以参考文档: http://www.jinbuguo.com/systemd/systemd-fstab-generator.html

在网络引导的方式中，一般使用iPXE，以支持更多样的场景。
比如，在[ipxe官网](https://ipxe.org/start)，有如下简介：

- boot from a web server via HTTP
- boot from an iSCSI SAN
- boot from a Fibre Channel SAN via FCoE
- boot from an AoE SAN
- boot from a wireless network
- boot from a wide-area network
- boot from an Infiniband network
- control the boot process with a script

后面的介绍会具体介绍compass ci 使用 iPXE 从网络引导操作系统的过程。

BootLoader 在加载 kernel和可能的initramfs文件之后，调用kernel。

#### 4. Kernel 加载 initramfs

内核将initramfs(初始RAM文件系统)归档文件解压到(当前为空的)rootfs(一个ramfs或者tmpfs类型的初始根文件系统)。
第一个提取的initramfs是在内核构建期间嵌入内核二进制文件中的initramfs，然后提取可能的外部initramfs文件。
因此，外部initramfs中的文件会覆盖嵌入式initramfs中的同名文件

> 这是计算机启动过程中可以访问的第一个根文件系统，它的作用是挂载真正的操作系统。
> 在某些场景下，initramfs 也可以作为最终的根文件系统。

然后，内核执行 initramfs 中的1号进程，现在一般是systemd。 

refer to: https://wiki.archlinux.org/title/Arch_boot_process#initramfs

#### 5. Initramfs 寻找并挂载根文件系统

initramfs 是初始内存文件系统，它通常和 kernel 文件一起存放在/boot分区中，每次安装新内核时都会生成一个新的 initramfs。

```
# ll /boot | grep -E "vmlinuz|initramfs" | grep $(uname -r)
-rwxr-xr-x. 1 root root 7.1M 2020-03-24 03:19 vmlinuz-4.19.90-2003.4.0.0036.oe1.aarch64
-rw-------. 1 root root  22M 2020-06-05 17:14 initramfs-4.19.90-2003.4.0.0036.oe1.aarch64.img
```
默认情况下，initramfs归档文件只包含特定计算机需要的驱动程序。这使得存档更小，并减少了计算机启动所需的时间。

refer to: https://wiki.archlinux.org/title/Arch_boot_process#initramfs

Initramfs 使用 dracut 进行管理，在一个安装好的系统上使用 `dracut` 命令可以直接创建一个适配当前运行内核的 initramfs 文件。
命令语法：`# dracut [--force] [/PATH/TO/new_image_name] [kernel version]`
> 其中 --force，表示覆盖/boot 目录下同名的 initramfs 文件。

Initramfs，也就是 dracut 的目的是挂载真正的根文件系统。
> refer to: https://www.man7.org/linux/man-pages/man7/dracut.bootup.7.html

上面 GRUB2 的配置文件中，"root=/dev/mapper/openeuler-root"  指定根文件系统设备。
在使用initrd的系统上，该参数由initrd解析。

查看 [dracut支持的内核参数](https://www.man7.org/linux/man-pages/man7/dracut.cmdline.7.html)
可以支持的选项如下：

- root=nfs:[<server-ip>:]<root-dir>[:<nfs-options>]
- root=/dev/nfs nfsroot=[<server-ip>:]<root-dir>[:<nfs-options>]
- root=cifs://[<username>[:<password>]@]<server-ip>:<root-dir>
- root=live:<url>
......

#### 6. Systemd 启动操作系统  

在真正的根文件系统挂载之后，systemd 要完成的事情如下：

- 挂载 /etc/fstab 所定义的文件系统，包括所有交换文件或分区
- 访问 /etc/systemd/system/default.target 来确定将主机引导至哪个状态或目标
- 按照 systemd 置文件的规则，递归启动操作系统需要的文件系统、服务和驱动程序
- 执行 /etc/rc.d/rc.local (需要文件存在，且有执行权限；兼容传统的 System V 系统)

使用`systemd-analyze critical-chain | grep target` 命令，查看：

  multi-user.target @39.632s
    └─network-online.target @14.727s
            └─basic.target @6.623s
	       └─sockets.target @6.603s
		   └─sysinit.target @6.479s
		         └─local-fs.target @5.959s
		             └─local-fs-pre.target @4.197s

systemd 中以 ".target" 为后缀的单元文件，封装了一个由 systemd 管理的启动目标单元，用于在启动过程中将一组单元汇聚到一个众所周知的同步点。
使用`systemctl list-dependencies multi-user.target` 命令，还可以看到更清晰的启动依赖及顺序关系。
启动过程是高度并行化的，因此特定目标单元到达的顺序不是确定的，但仍然遵循有限数量的顺序结构。

refer to: https://zhuanlan.zhihu.com/p/140273445

Systemd 启动日志查看：`journalctl -b`

#### 7. 登录界面

## iPXE

### iPXE在Linux启动过程中位置:

BIOS -> PXE -> iPXE -> Booting Kernel

### PXE与iPXE

pxe，预启动环境，使用网卡通过网络启动计算机的一种**机制**，支持DHCP、TFTP、HTTP、DNS等协议
> 对于Legacy的BIOS，Intel的网卡都会提供PXE ROM来支持；对于UEFI的BIOS，它有一套完整的网络协议栈来支持PXE启动

ipxe，是pxe的扩展版，提供了对HTTPS、NFS、FTP、iSCSI、EFI、VLAN等多种协议的支持。
> ipxe可以烧写在网卡的ROM中，也可以使用别的PXEboot固件链式加载iPXE的引导文件。
> 参考文档：[iPXE官网](https://ipxe.org/)

### iPXE编译
1. `git clone https://github.com/ipxe/ipxe.git`
> 如果因为网络下载不了，可使用加速器：git clone https://github.com.cnpmjs.org/ipxe/ipxe.git

2. `cd ipxe/src`
	如果是交叉边编译： `make CROSS=aarch64-linux-gnu- bin-arm64-efi/snp.efi`
	如果是本地编译： `make bin-x86_64-efi/snp.efi`

3. `ls .*/snp.efi`
> bin-arm64-efi/snp.efi  bin-x86_64-efi/snp.efi

备注：
1. 编译得到的是给 UEFI BIOS 加载的bootloader。
2. 编译环境的安装此处略过。

### iPXE命令介绍 

基础命令及其功能:

  dhcp    Automatically configure interfaces
  initrd  Download an image
  kernel  Download and select an executable image
  boot    boot an executable image

> 参考文档：[iPXE命令](https://ipxe.org/cmd)


## Compass-CI 使用 iPXE 通过网络启动系统的流程

### 图示：
```
	server			client
	  |			   |
	  |			   |
    DHCP（dnsmasq） <-------  PXE module  
	  |	      (1) 	   |		1. 客户端发动'discover'广播，会被 DHCP server 接收
	  |			   |
    DHCP（dnsmasq） ------->  PXE module
	  |	      (2)     	   | 		2. DHCP server 会按照配置，返回'offer'报文，包含ip、掩码、网关
	  |			   |
    DHCP（dnsmasq） <-------  PXE module
    	  |	      (3)	   |		3. 客户端通知DHCP，它在使用 PXE 启动
	  |			   |	  
    DHCP（dnsmasq） ------->  PXE module   
    	  |	      (4)	   |		4. DHCP server 发送 TFTP Server's IP 和 Boot Filename: xxx/snp.efi 给客户端
	  |			   |	  
    TFTP（dnsmasq） <-------  PXE module
    	  |	      (5)	   |		5. 客户端向 TFTP Server 请求 snp.efi 文件
	  |			   |	  
    TFTP（dnsmasq） ------->  PXE module   
    	  |	      (6)	   |		6. TFTP Server 发送 snp.efi 文件给客户端
	  |	      (7)	   |		7. 客户端执行 snp.efi 文件
	  |			   |
    DHCP（dnsmasq） <-------  iPXE module  
	  |	      (8) 	   |		8. 客户端发动'discover'广播，会被 DHCP server 接收
	  |			   |
    DHCP（dnsmasq） ------->  iPXE module
	  |	      (9)     	   | 		9. DHCP server 会按照配置，返回'offer'报文，包含ip、掩码、网关
	  |			   |
    DHCP（dnsmasq） <-------  iPXE module  
	  |	      (10) 	   |		10. 客户端通知DHCP，它在使用 iPXE 启动
	  |			   |
    DHCP（dnsmasq） ------->  iPXE module
	  |	      (11)     	   | 		11. DHCP server 发送 TFTP Server's IP 和 Boot Filename: boot.ipxe 给客户端
	  |			   |
    TFTP（dnsmasq） <-------  iPXE module
    	  |	      (12)	   |		12. 客户端向 TFTP Server 请求 boot.ipxe 文件
	  |			   |	  
    TFTP（dnsmasq） ------->  iPXE module   
    	  |	      (13)	   |		13. TFTP Server 发送 boot.ipxe 文件给客户端
	  |	      (14)	   |		14. 客户端 执行 boot.ipxe 脚本
	  |			   |
    scheduler 	<-----------  iPXE module  
	  |	      (15) 	   |		15. 客户端 chain http://${scheduler}:${port}/boot.ipxe/mac/${mac:hexhyp}
	  |			   |
    scheduler   ----------->  iPXE module
	  |	      (16)     	   | 		16. scheduler 根据mac 得到 Hostname，再得到 queues信息，返回'队列'中的任务给客户端 -> (18)
	  |	      (17)	   |		17. 如果此时队列中没有任务，客户端会一直等待，直到超时，重复(1)--(16) 
	  |			   |
    HTTPS（container）<-----  iPXE module  	## '任务信息'也是一个可执行的ipxe脚本
	  |	      (18) 	   |		18. 客户端向 HTTPS Server批量请求以命名以.cgz结尾的文件 ## iPXE 的 initrd 命令
	  |			   |
    HTTPS（container）------> iPXE module
	  |	      (19)     	   | 		19. HTTPS Server 批量发送 .cgz 文件给客户端
	  |			   |
    HTTPS（container）<-----  iPXE module
	  |	      (20)     	   | 		20. 客户端向 HTTPS Server 请求 kernel 镜像，并向内核传递参数 ## iPXE 的 kernel 命令
	  |			   |
    HTTPS（container）------> iPXE module
	  |	      (21)     	   | 		21. HTTPS Server 发送 kernel 镜像给客户端
	  |	      (22)     	   | 		22. iPXE 引导内核  ## iPXE 的 boot 命令
	  |			   |
	  |	      (23)      Kernel		23. 内核加载 Initramfs，启动 systemd
	  |			   |
	  |	      (24)      Initramfs	24. Initramfs 根据内核参数挂载根文件系统
	  |	      (25)         |		25. systemd startup
	  |			   |
	  |	      (26)	Systemd 	26. lkp-bootstrap.service run  # cci running
	  |			   |
	  |------------------------|

```

## 相关日志

### BISO -> PXE
```
"""
[Bds]Booting UEFI PXEv4 (MAC:446747E97965)
"""
```
### PXE 下载 snp.efi
```
"""
>>Start PXE over IPv4
Mac Addr: 44-67-47-E9-79-65.
  Station IP address is 172.168.178.59

  Server IP address is 172.168.131.2
  NBP filename is /tftpboot/ipxe/bin-arm64-efi/snp.efi
  NBP filesize is 236032 BytesChecking media [Pass]
Checking media [Pass]
	
 Downloading NBP file...

  NBP file downloaded successfully.
Loading driver at 0x0002EDD4000 EntryPoint=0x0002EDDA8F4 snp.efi
iPXE initialising devices...HinicSnpReceiveFilters()
"""
```

### PXE -> iPXE
```
"""
iPXE 1.20.1+ (gc6c9e) -- Open Source Network Boot Firmware -- http://ipxe.org
Features: DNS FTP HTTP HTTPS iSCSI NFS TFTP VLAN AoE EFI Menu
"""
```

#### iPXE 下载 boot.ipxe 脚本并执行
```
"""
net4: 44:67:47:e9:79:65 using SNP on SNP-0x2da34f98 (open)
  [Link:up, TX:0 TXE:0 RX:0 RXE:0]
Configuring (net4 44:67:47:e9:79:65)...... ok
net4: 172.168.178.59/255.255.0.0 gw 172.168.131.1
Next server: 172.168.131.2
Filename: boot.ipxe
tftp://172.168.131.2/boot.ipxe... ok
Unloading driver at 0x00000000000
boot.ipxe : 144 bytes [script]
http://172.168.131.2:3000/boot.ipxe/mac/44-67-47-e9-79-65.......................
................................................................................
"""
```

### Scheduler 发送'任务'给 iPXE，iPXE 向HTTPS Server 下载
```
"""
http://172.168.131.2:8800/initrd/osimage/openeuler/aarch64/20.03/20210609.0.cgz.
.. ok
Unloading driver at 0x00000000000
http://172.168.131.2:8000/os/openeuler/aarch64/20.03-2021-05-18-15-08-52/boot/mo
dules-4.19.90-2003.4.0.0036.oe1.aarch64.cgz... ok
Unloading driver at 0x00000000000
http://172.168.131.2:8800/initrd/deps/initramfs/debian/aarch64/sid/run-ipconfig_
20200904.cgz... ok
Unloading driver at 0x00000000000
http://172.168.131.2:8800/initrd/deps/initramfs/openeuler/aarch64/20.03/lkp/lkp_
20211026.cgz... ok
Unloading driver at 0x00000000000
"""
```

### iPXE 向 HTTPS Server 下载 kernel 镜像，然后 Booting (拿到了内核参数)  
```
"""
http://172.168.131.2:8000/os/openeuler/aarch64/20.03-2021-05-18-15-08-52/boot/vm
linuz-4.19.90-2003.4.0.0036.oe1.aarch64... ok
Loading driver at 0x0000EA66000 EntryPoint=0x0000F7DC900 
Unloading driver at 0x0000EA66000
Loading driver at 0x0000EA66000 EntryPoint=0x0000F7DC900 
EFI stub: Booting Linux Kernel...

[    0.000000] Kernel command line: vmlinuz-4.19.90-2003.4.0.0036.oe1.aarch64 user=lkp job=/lkp/scheduled/job.yaml ip=dhcp rootovl ro rdinit=/sbin/init prompt_ramdisk=0 initrd=20210609.0.cgz initrd=modules-4.19.90-2003.4.0.0036.oe1.aarch64.cgz initrd=run-ipconfig_20200904.cgz initrd=lkp_20211026.cgz initrd=job.cgz initrd=v2021.09.23.cgz initrd=2acd9aa658e3a4e6c2a03310d87b7fc2.cgz rootfs_disk=/dev/disk/by-id/ata-ST8000NM0055-1RM112_ZA1HM4ZK crashkernel=512M
"""
```

## 相关配置

### dhcp侧的配置

- 分配一段ip给client
```
dhcp-range=set:enp1,172.168.177.10,172.168.178.250,1440h 
``` 

- 根据client的架构类型，指定对应的ipxe程序文件
  参考：[dnsmasq文档](https://wiki.archlinux.org/title/Dnsmasq)； [RFC 4578](https://datatracker.ietf.org/doc/html/rfc4578)
```
dhcp-match=set:pxeclient-arm64,93,11 
dhcp-match=set:pxeclient-x64,93,7  

dhcp-boot=tag:pxeclient-arm64,/tftpboot/ipxe/bin-arm64-efi/snp.efi
dhcp-boot=tag:pxeclient-x64,/tftpboot/ipxe/bin-x86_64-efi/snp.efi
```

- 指定ipxe加载的脚本boot.ipxe
```
# dhcp-boot of boot.ipxe must be on the last line.
dhcp-boot=tag:ipxe,boot.ipxe
```

### boot.ipxe 脚本
```
#!ipxe
set scheduler 172.168.131.2
#set scheduler 172.17.0.1
set port 3000

chain http://${scheduler}:${port}/boot.ipxe/mac/${mac:hexhyp}

exit
```


#### scheduler 发送给客户端的'任务信息'（以vm测试机为例）
```
#!ipxe
  
initrd http://172.168.131.2:8800/initrd/osimage/openeuler/aarch64/20.03/20210609.0.cgz
initrd http://172.168.131.2:8000/os/openeuler/aarch64/20.03-2021-05-18-15-08-52/boot/modules-4.19.90-2003.4.0.0036.oe1.aarch64.cgz
initrd http://172.168.131.2:8800/initrd/deps/initramfs/debian/aarch64/sid/run-ipconfig_20200904.cgz
initrd http://172.168.131.2:8800/initrd/deps/initramfs/openeuler/aarch64/20.03/lkp/lkp_20211026.cgz
initrd http://172.168.131.2:8800/initrd/deps/initramfs/openeuler/aarch64/20.03/md/md_20201104.cgz
initrd http://172.168.131.2:8800/initrd/deps/initramfs/openeuler/aarch64/20.03/fs/fs_20210412.cgz
initrd http://172.168.131.2:8800/initrd/deps/initramfs/openeuler/aarch64/20.03/openeuler_docker/openeuler_docker_20211115.cgz
initrd http://172.168.131.2:8800/initrd/pkg/initramfs/openeuler/aarch64/20.03/openeuler_docker/1.0-1.cgz
initrd http://172.168.131.2:3000/job_initrd_tmpfs/z9.13138976/job.cgz
initrd http://172.168.131.2:8800/upload-files/lkp-tests/aarch64/v2021.09.23.cgz
initrd http://172.168.131.2:8800/upload-files/lkp-tests/08/08624540efe0e8de8b582ee73aef162c.cgz
kernel http://172.168.131.2:8000/os/openeuler/aarch64/20.03-2021-05-18-15-08-52/boot/vmlinuz-4.19.90-2003.4.0.0036.oe1.aarch64 user=lkp job=/lkp/scheduled/job.yaml \
ip=dhcp rootovl ro rdinit=/sbin/init prompt_ramdisk=0  initrd=20210609.0.cgz  initrd=modules-4.19.90-2003.4.0.0036.oe1.aarch64.cgz  initrd=run-ipconfig_20200904.cgz \  
initrd=lkp_20211026.cgz  initrd=md_20201104.cgz  initrd=fs_20210412.cgz  initrd=openeuler_docker_20211115.cgz  initrd=1.0-1.cgz  initrd=job.cgz \ initrd=v2021.09.23.cgz  initrd=08624540efe0e8de8b582ee73aef162c.cgz rootfs_disk=/dev/vdb crashkernel=256M
boot
```
