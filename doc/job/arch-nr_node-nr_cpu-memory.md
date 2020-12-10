# arch, nr_node, nr_cpu, memory

Meaning:
- Each test machine has some basic configurations, such as arch, nr_node, nr_cpu, memory
  these fields mean:
```SHELL
  arch:    the architecture of the machine.
  nr_node: number of NUMA nodes.
  nr_cpu:  number of logical CPUs.
  memory:  memory size of the machine.
```

- These fields are from the file which in $LAB_SRC/hosts.
- Here is an example of these fields in the host file:
```SHELL
  arch:    aarch64
  nr_node: 4
  nr_cpu:  96
  memory:  256G
```
