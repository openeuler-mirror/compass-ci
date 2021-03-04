# Summary
---------

`os_mount` defines the rootfs type.

The below types are supported:
  - nfs
  - cifs
  - initramfs
  - container
  - local

Usage example:

  ```shell
  submit -m -c borrow-1h.yaml testbox=vm-2p8g os_mount=nfs
  submit -m -c borrow-1h.yaml testbox=vm-2p8g os_mount=cifs
  submit -m -c borrow-1h.yaml testbox=vm-2p16g os_mount=initramfs
  submit -m -c borrow-1h.yaml testbox=dc-8g os_mount=container
  submit -m -c borrow-1h.yaml testbox=taishan200-2280-2s48p-256g os_mount=local
  ```

# os_mount=local
----------------

`nfs`, `cifs`, `initramfs`, `container`, rootfs of them all are in memory.

So if you want to run your job in disk file system, you need to specify `os_mount=local` in your job.yaml.

BTW, the job's rootfs will be placed on a logical volume.


## temporary rootfs data by default

If you only add `os_mount: local` in your job.yaml, the logical volume of rootfs will be deleted and re-created in initrd stage before every job executes.

The brief flow is as follows:

  ```
  1. boot and request scheduler for job.
  2. initrd stage:
    - firstly, we need two logical volume:
      ${src_lv} -- src logical volume:
        - will never boot from this lv, just use it as a source data, and take a snapshot of it to get the real boot logical volume.
        - src_lv=/dev/mapper/os-${os}_${os_arch}_${os_version}_${timestamp}
        - ${timestamp} is just a version number, which is the latest rootfs version on the nfs server in cluster.
      ${boot_lv} -- boot logical volume:
        - will boot from this lv.
        - boot_lv=/dev/mapper/os-${os}_${os_arch}_${os_version}
    - if ${src_lv} not exists: create it, and rsync the rootfs from cluster nfs server.
    - if ${boot_lv} exists: delete it.
    - create ${boot_lv} as the snapshot of ${src_lv}.
    - switch root to ${boot_lv}.
  3. boot the rootfs and execute the job.
  ```

## persistent rootfs data

When you need to persist the rootfs data of a job, and use it in the subsequent job(s), two fields in `kernel_custom_params` will help you: `save_root_partition`, `use_root_partition`.

The brief flow is as follows:

  ```
  1. boot and request scheduler for job.
  2. initrd stage:
    - firstly, we need two logical volume:
      ${src_lv} -- src logical volume:
        - if have ${use_root_partition}, src_lv=/dev/mapper/os-${os}_${os_arch}_${os_version}_${use_root_partition}
        - if no   ${use_root_partition}, src_lv=/dev/mapper/os-${os}_${os_arch}_${os_version}_${timestamp}
      ${boot_lv} -- boot logical volume:
        - if have ${save_root_partition}, boot_lv=/dev/mapper/os-${os}_${os_arch}_${os_version}_${save_root_partition}
        - if no   ${save_root_partition}, boot_lv=/dev/mapper/os-${os}_${os_arch}_${os_version}
    - if ${src_lv} not exists:
      - if have ${use_root_partition}, exit 1.
      - if no   ${use_root_partition}, create ${src_lv}, and rsync the rootfs from cluster nfs server.
      - if ${boot_lv} != ${src_lv}:
        - if ${boot_lv} exists: delete it
        - create ${boot_lv} as the snapshot of ${src_lv}.
      - switch root to ${boot_lv}.
  3. boot the rootfs and execute the job.
  ```

Demo usage:

  ```
  - in 20210218, you submit a job-20210218.yaml, and you want to persist the
    rootfs data of job-20210218.yaml so that it can be used by the subsequent
    jobs.
    Then you need add the follow field in your job-20210218.yaml:
        kernel_custom_params: save_root_partition=zhangsan_local_for_iperf_20210218

  - in 20210219, you submit a job-20210219.yaml, and you want to use the rootfs
    data of job-20210218.yaml.
    Then you need add the follow field in your job-20210219.yaml:
        kernel_custom_params: use_root_partition=zhangsan_local_for_iperf_20210218
  ```

Notes:
  - obviously, `save_root_partition` and `use_root_partition` must be the same, and unique.
  - you must `save_root_partition` firstly, then you can `use_root_partition`. otherwise, your job will fail.

## work flow

1. user submit job

    job fields:
    ```yaml
    os: openeuler
    os_arch: aarch64
    os_version: 20.03
    os_mount: local
    kernel_custom_params: use_root_partition=zhangsan_local_for_iperf_20210218 save_root_partition=zhangsan_local_for_iperf_20210219
    ```

2. scheduler return the custom_ipxe to testbox

    ```
    #!ipxe
    dhcp
    initrd http://${http_server_ip}:${http_server_port}/os/openeuler/aarch64/20.03-iso-snapshots/${timestamp}/initrd.lkp
    kernel http://${http_server_ip}:${http_server_port}/os/openeuler/aarch64/20.03-iso-snapshots/${timestamp}/boot/vmlinuz root=/dev/mapper/os-openeuler_aarch64_20.03 rootfs_src=${nfs_server_ip}:os/openeuler/aarch64/20.03-iso-snapshots/${timestamp} initrd=initrd.lkp ${kernel_custom_params}
    boot
    ```

3. dracut step of boot

    ```bash
    analyze_kernel_cmdline_params()
    {
        for i in $(cat /proc/cmdline)
        do
                [ "$i" =~ "rootfs_src=" ] && export ROOTFS_SRC=${i#rootfs_src=}
        done

        [ -z "${ROOTFS_SRC}" ] && die "cannot find var in kernel cmdline params: rootfs_src"

        export TIMESTAMP=$(basename ${ROOTFS_SRC})
    }

    rsync_src_lv()
    {
        local src_lv=$1

        lvdisplay ${src_lv} > /dev/null && return

        # create logical volume
        lvcreate --size 10G --name $(basename ${src_lv}) os || exit

        # rsync nfsroot to ${src_lv}
        mount -t nfs ${ROOTFS_SRC} /mnt
        mkdir /mnt1 && mount ${src_lv} /mnt1
        cp -a /mnt/. /mnt1/
        umount /mnt /mnt1

        # change permission of ${src_lv} to readonly
        lvchange --permission r ${src_lv}
    }

    snapshot_boot_lv()
    {
        local src_lv=$1
        local boot_lv=$2

        [ "$src_lv" == "$boot_lv" ] && return

        lvremove --force ${boot_lv}
        lvcreate --size 10G --name $(basename ${boot_lv}) --snapshot ${src_lv} || exit
    }

    main()
    {
        analyze_kernel_cmdline_params

        if [ -z "${use_root_partition}" ]; then
                src_lv="/dev/mapper/os-openeuler_aarch64_20.03_${TIMESTAMP}"
                rsync_src_lv ${src_lv}
        else
                src_lv="/dev/mapper/os-openeuler_aarch64_20.03_${use_root_partition}"
                lvdisplay ${src_lv} > /dev/null || exit
        fi

        if [ -z "${save_root_partition}" ]; then
                boot_lv="/dev/mapper/os-openeuler_aarch64_20.03"
        else
                boot_lv="/dev/mapper/os-openeuler_aarch64_20.03_${save_root_partition}"
        fi

        snapshot_boot_lv ${src_lv} ${boot_lv}
        boot_from_boot_lv
    }

    main
    ```

4. execute the job
