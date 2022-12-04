# Summary
=========

`rootfs_disk` defines a list of disks, these disks will be combined into one volume group(os),
this volume group will have multiple logical volume, storing multiple rootfs, each of these
logical volume corresponds to a rootfs, such as follow:
    /dev/mapper/
    .
    ├── os-openeuler_aarch64_20.03
    ├── os-openeuler_aarch64_20.03_{timestamp}
    ├── os-openeuler_aarch64_20.03_sp1
    ├── os-openeuler_aarch64_20.03_sp1_{timestamp}
    └── ...

Addition:
1. `/dev/mapper/os-{os}_{os_arch}_{os_version}_{timestamp}`
  - is a readonly logical volume
  - used for backup and rollback

2. `/dev/mapper/os-{os}_{os_arch}_{os_version}`
  - is a read write logical volume
  - use for boot and run job
  - defaultly, this logical volume will be wiped before every job run

3. every logical volume default size: 20G

4. more info can refer os_mount.md
