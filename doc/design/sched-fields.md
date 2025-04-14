# job sched fields

    Field Name          Values
    ==============================================
    sched.tbox_type     hw|vm|dc
    sched.tbox_group    dc-8g|taishan200-2280-2s64p-256g
    sched.testbox       taishan200-2280-2s48p-256g--a61

以上全部合入testbox字段，方便用户.

```
    Field Name          Values
    ==============================================
    testbox             hw|vm|dc
                        dc-8g|vm-2p8g|taishan200-2280-2s64p-256g
                        taishan200-2280-2s48p-256g--a61
    arch                aarch64|x86_64
    need_memory         8|8g|8G

    # scheduler input/output
    target_machines     [taishan200-2280-2s48p-256g--a61, ...]

    # scheduler output, reflects the real run location
    hostname            $(hostname) in testbox
    host_machine        for hw, =hostname in testbox
                        for vm/dc, =hostname in multi-qemu/docker testbox

    # possible future scheduler input
    cache_dirs = [ccache/gcc, git/linux, ...]

    sched.cpu_model
    sched.nr_cpu
    sched.nr_hdd
    sched.nr_ssd
    sched.devices
```
