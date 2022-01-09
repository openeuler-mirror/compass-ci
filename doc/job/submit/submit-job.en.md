# submit Command Description

### Prerequisites

The Compass-CI client has been installed. For details, see [Installing the Local Compass-CI Client](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/user-guide/install-cci-client.md).

### Purpose

You can run the **submit** command to submit a test task. This command provides multiple options to help you submit tasks more flexibly. You can enter the **submit** command in the command line to view the help information and use the command flexibly as required.

### Basic Usage

The test task is submitted in a YAML file. You need to prepare the YAML file of the test task. This document uses **iperf.yaml** as an example. Run the following command to submit a test task:

```
submit iperf.yaml
```

The following message is displayed:

```shell
hi8109@account-vm ~% submit iperf.yaml
submit iperf.yaml, got job_id=z9.173924
```

The **testbox** field has been added to the **iperf.yaml** file shown in this document. If the YAML file does not contain this field, an error is reported:

```shell
hi8109@account-vm ~% submit iperf.yaml
submit iperf.yaml failed, got job_id=0, error: Missing required job key: 'testbox'
```

You can add the **testbox** field to the YAML file or run the following command:

```
submit iperf.yaml testbox=vm-2p8g
```

The value of the **testbox** field specifies the required test machine. You can run the `ls` command to view the available test machines in the `lkp-tests/hosts` path, as shown in the following figure:

```shell
hi8109@account-vm ~/lkp-tests/hosts% ll
total 120K
-rw-r--r--. 1 root root  76 2020-11-02 14:54 vm-snb
-rw-r--r--. 1 root root  64 2020-11-02 14:54 vm-pxe-hi1620-2p8g
-rw-r--r--. 1 root root  64 2020-11-02 14:54 vm-pxe-hi1620-2p4g
-rw-r--r--. 1 root root  64 2020-11-02 14:54 vm-pxe-hi1620-2p1g
-rw-r--r--. 1 root root  64 2020-11-02 14:54 vm-pxe-hi1620-1p1g
-rw-r--r--. 1 root root  75 2020-11-02 14:54 vm-hi1620-2p8g
-rw-r--r--. 1 root root  75 2020-11-02 14:54 vm-hi1620-2p4g
-rw-r--r--. 1 root root  75 2020-11-02 14:54 vm-hi1620-2p1g
-rw-r--r--. 1 root root  75 2020-11-02 14:54 vm-hi1620-1p1g
-rw-r--r--. 1 root root  61 2020-11-02 14:54 vm-2p8g-pxe
-rw-r--r--. 1 root root  61 2020-11-02 14:54 vm-2p8g
-rw-r--r--. 1 root root  61 2020-11-02 14:54 vm-2p4g-pxe
-rw-r--r--. 1 root root  61 2020-11-02 14:54 vm-2p4g
-rw-r--r--. 1 root root  61 2020-11-02 14:54 vm-2p1g-pxe
-rw-r--r--. 1 root root  61 2020-11-02 14:54 vm-2p1g
-rw-r--r--. 1 root root  61 2020-11-02 14:54 vm-1p1g-pxe
-rw-r--r--. 1 root root  61 2020-11-02 14:54 vm-1p1g
-rw-r--r--. 1 root root  14 2020-11-02 14:54 taishan200-2280-2s64p-256g
-rw-r--r--. 1 root root 497 2020-11-02 14:54 lkp-skl-d01
-rw-r--r--. 1 root root 574 2020-11-02 14:54 lkp-ivb-d04
-rw-r--r--. 1 root root 606 2020-11-02 14:54 lkp-ivb-d02
-rw-r--r--. 1 root root 384 2020-11-02 14:54 lkp-ivb-d01
-rw-r--r--. 1 root root 388 2020-11-02 14:54 lkp-hsw-d01
-rw-r--r--. 1 root root 385 2020-11-02 14:54 lkp-bdw-de1
-rw-r--r--. 1 root root  11 2020-11-02 14:54 dc-8g
-rw-r--r--. 1 root root  11 2020-11-02 14:54 dc-4g
-rw-r--r--. 1 root root  11 2020-11-02 14:54 dc-2g
-rw-r--r--. 1 root root  11 2020-11-02 14:54 dc-1g
-rw-r--r--. 1 root root  13 2020-11-02 14:54 2288hv5-2s64p
-rw-r--r--. 1 root root  74 2020-11-02 14:54 vm-snb-i386
```

> ![](./../../icons/icon-note.gif) **Note**
>
> Use the equal sign (=) to update the fields in the YAML file. The priority of the ***=*** varies with its position in the command line.
>
> * In the **submit iperf.yaml testbox=vm-2p8g** command, the **=** is defined after the YAML file. As a result, the priority of the **=** is higher than that of the YAML file. **testbox=vm-2p8g** overrides the **testbox** field defined in the YAML file.
> * In the **submit testbox=vm-2p8g iperf.yaml** command, the **=** is defined before the YAML file. As a result, the priority of **=** is lower than that of the YAML file. **testbox=vm-2p8g** does not override the **testbox** field defined in the YAML file. A value is assigned only when the YAML file does not contain the **testbox** field.

### Advanced Usage

The following figure shows the options of the **submit** command:

```shell
hi8109@account-vm ~% submit
Usage: submit [options] job1.yaml job2.yaml ...
       submit test jobs to the scheduler

options:
    -s, --set 'KEY: VALUE'           add YAML hash to job
    -o, --output DIR                 save job yaml to DIR/
    -a, --auto-define-files          auto add define_files
    -c, --connect                    auto connect to the host
    -m, --monitor                    monitor job status: use -m 'KEY: VALUE' to add rule
        --my-queue                   add to my queue
```

* **Usage of -s**

  You can use the **-s'KEY:VALUE'** parameter to update the key-value pair to the submitted task. An example is shown in the following figure:

  ```
  submit -s 'testbox: vm-2p8g' iperf.yaml
  ```

  * If the **iperf.yaml** file does not contain **testbox: vm-2p8g**, the field will be added to the submitted task.
  * If the **iperf.yaml** file contains the **testbox** field but the value is not **vm-2p8g**, the value of **testbox** in the submitted task will be updated as **vm-2p8g**.

* **Usage of -o**

  You can run the **-o DIR** command to save the generated YAML file to the specified directory **DIR**. An example is shown in the following figure:

  ```
  submit iperf.yaml testbox=vm-2p8g -o /tmp
  ```

  After the command is executed, the YAML file that has been processed by the **submit** command is generated in the specified directory.

* **Usage of -a**

  If the **lkp-tests** on the client is changed in the test case, you need to use the **-a** option for adaptation. Synchronize the modification made in the **lkp-tests** on the client to the server, and generate a customized test script on the test machine. An example is shown in the following figure:

  ```
  submit -a iperf.yaml
  ```

* **Usage of -m**

  You can use the **-m** parameter to enable the task monitoring function and print the status information during the task execution on the console. In this way, you can monitor the execution process of the test task in real time. An example is shown in the following figure:

  ```
  submit -m iperf.yaml
  ```

  The following information is displayed on the console:

  ```shell
  hi8109@account-vm ~% submit -m iperf.yaml
  submit iperf.yaml, got job_id=z9.173923
  query=>{"job_id":["z9.173923"]}
  connect to ws://172.168.131.2:20001/filter
  {"job_id":"z9.173923","message":"","job_state":"submit","result_root":"/srv/result/iperf/2020-11-30/vm-2p8g/openeuler-20.03-aarch6
  {"job_id": "z9.173923", "result_root": "/srv/result/iperf/2020-11-30/vm-2p8g/openeuler-20.03-aarch64/tcp-30/z9.173923", "job_state
  {"job_id": "z9.173923", "job_state": "boot"}
  {"job_id": "z9.173923", "job_state": "download"}
  {"time":"2020-11-30 20:28:16","mac":"0a-f5-9f-83-62-ea","ip":"172.18.192.21","job_id":"z9.173923","state":"running","testbox":"vm-
  {"job_state":"running","job_id":"z9.173923"}
  {"job_state":"post_run","job_id":"z9.173923"}
  {"start_time":"2020-11-30 12:25:15","end_time":"2020-11-30 12:25:45","loadavg":"1.12 0.38 0.14 1/105 1956","job_id":"z9.173923"}
  {"job_state":"finished","job_id":"z9.173923"}
  {"job_id": "z9.173923", "job_state": "complete"}
  {"time":"2020-11-30 20:28:54","mac":"0a-f5-9f-83-62-ea","ip":"172.18.192.21","job_id":"z9.173923","state":"rebooting","testbox":"v
  {"job_id": "z9.173923", "job_state": "extract_finished"}
  connection closed: normal
  ```

* **Usage of -c**

  The **-c** parameter must be used together with the **-m** parameter to implement the automatic login function in the task of applying for a device.

  An example is shown in the following figure:

  ```
  submit -m -c borrow-1h.yaml
  ```

  After submitting a task of applying for a device, you will receive the returned login information, such as `ssh ip -p port`. After adding the **-c** parameter, you can log in to the executor without manually entering the SSH login command.

  The following information is displayed on the console:

  ```shell
  hi8109@account-vm ~% submit -m -c borrow-1h.yaml
  submit borrow-1h.yaml, got job_id=z9.173925
  query=>{"job_id":["z9.173925"]}
  connect to ws://172.168.131.2:20001/filter
  {"job_id":"z9.173925","message":"","job_state":"submit","result_root":"/srv/result/borrow/2020-11-30/vm-2p8g/openeuler-20.03-aarch
  {"job_id": "z9.173925", "result_root": "/srv/result/borrow/2020-11-30/vm-2p8g/openeuler-20.03-aarch64/3600/z9.173925", "job_state"
  {"job_id": "z9.173925", "job_state": "boot"}
  {"job_id": "z9.173925", "job_state": "download"}
  {"time":"2020-11-30 20:35:04","mac":"0a-24-5d-c8-aa-d0","ip":"172.18.101.4","job_id":"z9.173925","state":"running","testbox":"vm-2
  {"job_state":"running","job_id":"z9.173925"}
  {"job_id": "z9.173925", "state": "set ssh port", "ssh_port": "50200", "tbox_name": "vm-2p8g.taishan200-2280-2s48p-256g--a52-7"}
  Host 172.168.131.2 not found in /home/hi8109/.ssh/known_hosts
  Warning: Permanently added '[172.168.131.2]:50200' (ECDSA) to the list of known hosts.
  Last login: Wed Sep 23 11:10:58 2020


  Welcome to 4.19.90-2003.4.0.0036.oe1.aarch64

  System information as of time:  Mon Nov 30 12:32:04 CST 2020

  System load:    0.50
  Processes:      105
  Memory used:    6.1%
  Swap used:      0.0%
  Usage On:       89%
  IP address:     172.17.0.1
  Users online:   1



  root@vm-2p8g ~#
  ```

  You log in to the executor successfully.
