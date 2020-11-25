# os, os_version, os_arch

Meaning:
- Each test tells which os it needs, and the os_version, os_arch are also need to be specified,
  then the machine will run an os according to these three fields.
- The os, os_version, os_arch are the key for users to specify the os related parameters.
- If os, os_version, os_arch are not given by users, it will use the default openeuler os related parameters.
- Here are some examples:
	os		os_version		os_arch
	openeuler	20.03, 1.0		aarch64, x86_64
	debian		sid, 10			aarch64, x86_64
	centos		7.6, 7.8		aarch64, x86_64
	...

Usage example:
- submit iperf.yaml testbox=vm-2p8g os=openeuler os_arch=aarch64 os_version=20.03
