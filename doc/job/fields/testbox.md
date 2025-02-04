# testbox name, queue and config

1) 测试机命名规范

1.1) -N rule for tbox_group:

        tbox_group-N

1.2) guest.host rule for vm/docker:

        ${vm_tbox_group}-N.$host_testbox
        ${dc_tbox_group}-N.$host_testbox

Example:

        vm-2p8g-N.taishan200-2280-2s48p-256g--a101

2) 测试机与队列的关系

可以明确指定队列, 或者使用默认队列.

2.1) on submit job, support 2 fields

        queue: taishan200-2280-2s48p-256g--a101 (HW default)
        queue: vm-2p8g.aarch64                  (VM default)
        subqueue: {{my_email}}

2.2) in daemon/multi-qemu, support parameter

        queues:
        - q1
        - q2

VM default: 2 queues
        - vm-2p8g.taishan200-2280-2s48p-256g--a101 (tbox_group)
        - vm-2p8g.aarch64 (vm_tbox_group.arch)

HW default: 1 queue
        - taishan200-2280-2s48p-256g--a101 (tbox_group)

3) 测试机与配置的关系

3.1) vm测试机的arch设置

- hosts/vm-2p8g 没有'arch'字段
- on submit job, specify 'arch'
- in multi-qemu, specify 'arch' or normally by default, inherit host arch

3.2) 多台物理机，共享基本配置文件，同时有自己的特殊配置项（一般是磁盘）

        hosts/taishan200-2280-2s48p-256g
                nr_node: 2
                nr_cpu: 28
                memory: 256g

        hosts/taishan200-2280-2s48p-256g--a101
                <<: hosts/taishan200-2280-2s48p-256g
                hdd_partitions: xxx
