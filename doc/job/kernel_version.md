# kernel_version

Meaning:
- Every os has its kernel, however an os can start with different kernels according to different need.
- kernel_version is a key for users to specify a kernel version.
- If kernel_version is not given by users, it will use the default one.
- Here are the kernel versions we support for different os:
	openeuler/aarch64/1.0
	- 4.19.90-vhulk2001.1.0.0026.aarch64(default)

	openeuler/aarch64/20.03
	- 4.19.90-2003.4.0.0036.oe1.aarch64(default)
	- 4.19.90-mysql
	- 4.19.90-nginx

	debian/aarch64/sid
	- 5.4.0-4-arm64(default)
	- 5.8.0-1-arm64

	centos/aarch64/7.6.1810
	- 4.14.0-115.el7.0.1.aarch64(default)

	centos/aarch64/7.8.2003
	- 4.18.0-147.8.1.el7(default)

	centos/aarch64/8.1.1911
	- 4.18.0-147.el8(default)

```bash
Related files:
- In initramfs boot process, every kernel version is related with a vmlinuz, module and headers.
- Files like below under $boot_dir, an example $boot_dir can be "/srv/os/openeuler/aarch64/20.03/boot".
├── headers-4.19.90-2003.4.0.0036.oe1.aarch64.cgz
├── modules-4.19.90-2003.4.0.0036.oe1.aarch64.cgz
├── vmlinuz-4.19.90-2003.4.0.0036.oe1.aarch64
└── vmlinuz -> vmlinuz-4.19.90-2003.4.0.0036.oe1.aarch64
```

Usage example:
- submit iperf.yaml testbox=vm-2p8g queue=vm-2p8g~$USER os=openeuler os_arch=aarch64 os_version=20.03 runtime=20 kernel_version=4.19.90-2003.4.0.0036.oe1.aarch64
