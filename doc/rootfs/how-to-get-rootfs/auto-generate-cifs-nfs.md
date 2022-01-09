#### 4.2.2.2 自动化制作os_mount=cifs/nfs的rootfs

**说明：由于自动化天然有其有限性，故此种方式有其支持的[iso范围](https://gitee.com/ycvayne/iso2qcow2/tree/master/conf/ks)，如果需要制作的iso版本不在支持的iso范围中，请参考下面的手动安装iso制作rootfs部分**

在本地compass-ci集群中，提交iso2rootfs.yaml即可

```
zhangsan@localhost ~% cat iso2rootfs-21.09.yaml
suite: iso2rootfs
category: benchmark
iso2rootfs:
  #################
  # iso related fields to be used to generate rootfs
  #################

  iso_os: openeuler
  iso_arch: aarch64
  iso_version: 21.09

  #################
  # place the result rootfs related fields
  #################

  # 1. Result rootfs will be placed in the following location on the
  #    remote file server:
  #    - {remote_file_server}/{rootfs_path}/{iso_os}/{iso_arch}/
  # 2. Remote file server protocols current supported:
  #    - nfs
  #    - cifs
  rootfs_protocol: cifs
  rootfs_server: 1.1.1.1
  rootfs_path: os-rw
  rootfs_mount_param: guest,vers=1.0,noacl,nouser_xattr

  initramfs_protocol: cifs
  initramfs_server: 1.1.1.1
  initramfs_path: initrd/osimage
  initramfs_mount_param: port=446,guest,vers=1.0,noacl,nouser_xattr

  #################
  # config rootfs related fields
  #################

  # you can config add some configurations of the result rootfs.
  # supported fields:
  # - dns: will config /etc/resolv.conf.
  # - no_selinux: will disable selinux in /etc/selinux/config.
  # - no_fstab: will comment all line in /etc/fstab.
  # - enable_repos: will enable all repo file of result rootfs.
  config_rootfs: no_selinux, no_fstab

  ## install pkgs for result rootfs
  ## - example: vim, git, xxx
  rootfs_install_pkgs:

  #################
  # iso srouce related fields
  #################

  # iso url which you want generate rootfs from
  # - demo:
  #   iso_url: http://1.1.1.1/openEuler-20.03-LTS-aarch64-LTS/openEuler-20.03-LTS-aarch64-dvd.iso

  iso_url: http://1.1.1.1:8000/os/install/iso/openeuler/aarch64/21.09/openEuler-21.09-aarch64-dvd.iso

  # dailybuild_iso_url_file:
  # - The `dailybuild iso url file` content is the url of a iso.
  # - The iso checksum file also exists on the network, and the checksum file path is "{dailybuild_iso_url}.check256sum"
  # - if your have this field, the above `iso_url` field will be useless.
  # - demo:
  #   dailybuild_iso_url_file: http://1.1.1.1/dailybuilds/openEuler-20.03-LTS-aarch64-LTS/release_iso
  #     root@localhost ~% curl http://1.1.1.1/dailybuilds/openEuler-20.03-LTS-aarch64-LTS/release_iso
  #     http://1.1.1.1//dailybuilds/openEuler-20.03-LTS-aarch64-LTS/1970-01-01-00-00-00/openEuler-20.03-LTS-aarch64-dvd.iso
  dailybuild_iso_url_file:

  #################
  # submit test yaml related fields
  #################

  # submit target tests yaml
  ## 1. You can add as many jobs as you like.
  ## 2. The following three fields is required for every test job.
  test1_yaml: iperf.yaml
  test1_os_mount: initramfs
  test1_testbox: vm-2p16g
  ## the following three fields is required when your job.yaml and
  ## script for this test are from the internet.
  test1_git_url:
  test1_git_yaml:
  test1_git_script:

secrets:
  MY_EMAIL: XXXXXXXXXXX@163.com
  MY_NAME: zhangsan
  MY_TOKEN: XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
zhangsan@localhost ~% #submit -m ./iso2rootfs-21.09.yaml testbox=taishan200-2280-2s64p-128g--a108
```
