# 使用LVM划分独立分区
由于compass-ci集群服务端运行过程中会占用一定大小的空间，如果不提前划分独立分区，容易产生根目录空间不足导致服务无法正常运行的问题。
为方便管理空间，建议为/var/lib/docker和/srv/result划分独立分区各200G。

- 查看可使用的硬盘
```
~# lsblk
NAME       MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
sda          8:0    0  1.1T  0 disk
sdb          8:16   0  1.1T  0 disk
sdc          8:32   0  1.1T  0 disk
sdd          8:48   0  1.1T  0 disk
```

本文选择其中一块/dev/sda 大小为1.1T的硬盘为例，在sda上创建两个各200G的逻辑卷用于挂载/var/lib/docker和/srv/result目录。

- 格式化硬盘
```
~# mkfs.ext4 /dev/sda
mke2fs 1.45.3 (14-Jul-2019)
/dev/sda contains a linux_raid_member file system labelled '0'
Proceed anyway? (y,N) y
Creating filesystem with 293028240 4k blocks and 73261056 inodes
Filesystem UUID: f3464361-9c41-4cbf-a272-02d0d5926e40
Superblock backups stored on blocks:
        32768, 98304, 163840, 229376, 294912, 819200, 884736, 1605632, 2654208,
        4096000, 7962624, 11239424, 20480000, 23887872, 71663616, 78675968,
        102400000, 214990848

Allocating group tables: done
Writing inode tables: done
Creating journal (262144 blocks): done
Writing superblocks and filesystem accounting information: done
```

- 创建物理卷
```
~# pvcreate /dev/sda
WARNING: ext4 signature detected on /dev/sda at offset 1080. Wipe it? [y/n]: y
  Wiping ext4 signature on /dev/sda.
  Physical volume "/dev/sda" successfully created.
```

- 查看物理卷
```
~# pvs
  PV         VG Fmt  Attr PSize PFree
  /dev/sda      lvm2 ---  1.09t   1.09t
```

- 创建逻辑卷组
```
~# vgcreate vg-result /dev/sda
  Volume group "vg-result" successfully created
```

- 查看逻辑卷组
```
~# vgs
  VG        #PV #LV #SN Attr   VSize VFree
  vg-result   1   0   0 wz--n- 1.09t   1.09t
```

- 创建逻辑卷 
```
~# lvcreate -n lv-result -L 200G vg-result
  Logical volume "lv-result" created.

~# lvcreate -n lv-docker -L 200G vg-result
  Logical volume "lv-docker" created.
```

- 查看逻辑卷 
```
~# lvs
  LV                                                 VG        Attr       LSize   Pool Origin              Data%  Meta%  Move Log Cpy%Sync Convert
  lv-docker                                          vg-result -wi-a----- 200.00g                                                                                           
  lv-result                                          vg-result -wi-ao---- 200.00g                                                                                           
  ```

- 创建要挂载的目录/srv/result和/var/lib/docker
```
~# mkdir -p /srv/result /var/lib/docker

- 格式化逻辑卷lv-result
~# mkfs.ext4 /dev/vg-result/lv-result
mke2fs 1.45.3 (14-Jul-2019)
Creating filesystem with 52428800 4k blocks and 13107200 inodes
Filesystem UUID: f5d489e5-fd9a-4df7-9673-0dce6dafaf28
Superblock backups stored on blocks:
        32768, 98304, 163840, 229376, 294912, 819200, 884736, 1605632, 2654208,
        4096000, 7962624, 11239424, 20480000, 23887872

Allocating group tables: done
Writing inode tables: done
Creating journal (262144 blocks): done
Writing superblocks and filesystem accounting information: done
```

- 格式化逻辑卷lv-docker
```
~# mkfs.ext4 /dev/vg-result/lv-docker
mke2fs 1.45.3 (14-Jul-2019)
Creating filesystem with 52428800 4k blocks and 13107200 inodes
Filesystem UUID: 675c84ba-0ed6-41ac-ad34-a57d2df8ce18
Superblock backups stored on blocks:
        32768, 98304, 163840, 229376, 294912, 819200, 884736, 1605632, 2654208,
        4096000, 7962624, 11239424, 20480000, 23887872

Allocating group tables: done
Writing inode tables: done
Creating journal (262144 blocks): done
Writing superblocks and filesystem accounting information: done
```

- 挂载/srv/result 到逻辑卷/dev/vg-result/lv-result
```
~# mount /dev/vg-result/lv-result /srv/result
```

- 挂载/var/lib/docker到逻辑卷/dev/vg-result/lv-docker
```
~# mount /dev/vg-result/lv-docker /var/lib/docker
```

- 再次查看硬盘
```
~# lsblk
NAME                    MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
sda                       8:0    0  1.1T  0 disk
├─vg--result-lv--result 253:0    0  200G  0 lvm  /srv/result
└─vg--result-lv--docker 253:1    0  200G  0 lvm  /var/lib/docker
sdb                       8:16   0  1.1T  0 disk
sdc                       8:32   0  1.1T  0 disk
sdd                       8:48   0  1.1T  0 disk
```

- 将分区信息写到/etc/fstab
为避免物理机重启后导致分区失效，还需要将分区配置写入/etc/fstab中
```
~# vi /etc/fstab
/dev/vg-result/lv-docker  /var/lib/docker        ext4    defaults        0 0
/dev/vg-result/lv-result  /srv/result            ext4    defaults        0 0
```
