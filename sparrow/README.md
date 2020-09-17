Deploy a mini instance in one single machine.

Prepare:
	1. hardware
		Server: at least prepare a server
		ProductType: ThaiShan200-2280
		Arch: aarch64
		Memory: 8G
		CPU: 64 nuclear
		DiskSpace: 500G
	
	2. software
		OS: openEuler-aarch64-20.03 LTS
		git: suggest 2.23.0
	
	3. network
		Internet is available

	4. /os for store rootfs
		>= 300G

Steps:
	umask 002
	git clone https://gitee.com/wu_fengguang/crystal-ci.git
	cd crystal-ci/sparrow
	./install-tiny
