# Prerequisites

Ensure that you have performed the following operations according to the [apply-account.md](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/apply-account.md):

- Send an email to apply for an account.
- Receive an email from compass-ci-reply@qq.com.
- Configure the local environment.

# Applying for a Test Machine (VM)

1. Generate a local RSA private-public key pair.

   ```shell
   hi684@account-vm ~% ssh-keygen -t rsa
   Generating public/private rsa key pair.
   Enter file in which to save the key (/home/hi684/.ssh/id_rsa):
   Created directory '/home/hi684/.ssh'.
   Enter passphrase (empty for no passphrase):
   Enter same passphrase again:
   Your identification has been saved in /home/hi684/.ssh/id_rsa.
   Your public key has been saved in /home/hi684/.ssh/id_rsa.pub.
   The key fingerprint is:
   SHA256:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx hi684@account-vm
   The key's randomart image is:
   +---[RSA 2048]----+
   |xxxxxxxxxxxxxxxxx|
   |xxxxxxxxxxxxxxxxx|
   |xxxxxxxxxxxxxxxxx|
   |xxxxxxxxxxxxxxxxx|
   |xxxxxxxxxxxxxxxxx|
   |xxxxxxxxxxxxxxxxx|
   |xxxxxxxxxxxxxxxxx|
   |xxxxxxxxxxxxxxxxx|
   |xxxxxxxxxxxxxxxxx|
   +----[SHA256]-----+
   hi684@account-vm ~% ls -hla .ssh
   total 16K
   drwx------. 2 hi684 hi684 4.0K Nov 26 16:37 .
   drwx------. 7 hi684 hi684 4.0K Nov 26 16:37 ..
   -rw-------. 1 hi684 hi684 1.8K Nov 26 16:37 id_rsa
   -rw-r--r--. 1 hi684 hi684  398 Nov 26 16:37 id_rsa.pub
   ```

2. Select the YAML file as required.

   A **lkp-tests** folder is stored in each user directory `/home/${USER}`.

   ```shell
   hi684@account-vm ~% cd lkp-tests/jobs
   hi684@account-vm ~/lkp-tests/jobs% ls -hl borrow-*
   -rw-r--r--. 1 root root  53 Nov  2 14:54 borrow-10d.yaml
   -rw-r--r--. 1 root root  64 Nov  2 14:54 borrow-1d.yaml
   -rw-r--r--. 1 root root 235 Nov 19 15:27 borrow-1h.yaml
   ```

3. Submit the YAML file and connect to the test machine (VM).

   ```shell
   hi684@account-vm ~/lkp-tests/jobs% submit -c -m testbox=vm-2p8g borrow-1h.yaml
   submit borrow-1h.yaml, got job_id=z9.170593
   query=>{"job_id":["z9.170593"]}
   connect to ws://172.168.131.2:11310/filter
   {"job_id":"z9.170593","message":"","job_state":"submit","result_root":"/srv/result/borrow/2020-11-26/vm-2p8g/openeuler-20.03-aarch64/3600/z9.170593"}
   {"job_id": "z9.170593", "result_root": "/srv/result/borrow/2020-11-26/vm-2p8g/openeuler-20.03-aarch64/3600/z9.170593", "job_state": "set result root"}
   {"job_id": "z9.170593", "job_state": "boot"}
   {"job_id": "z9.170593", "job_state": "download"}
   {"time":"2020-11-26 14:45:06","mac":"0a-1f-0d-3c-91-5c","ip":"172.18.156.13","job_id":"z9.170593","state":"running","testbox":"vm-2p8g.taishan200-2280-2s64p-256g--a38-12"}
   {"job_state":"running","job_id":"z9.170593"}
   {"job_id": "z9.170593", "state": "set ssh port", "ssh_port": "51840", "tbox_name": "vm-2p8g.taishan200-2280-2s64p-256g--a38-12"}
   Host 172.168.131.2 not found in /home/hi684/.ssh/known_hosts
   Warning: Permanently added '[172.168.131.2]:51840' (ECDSA) to the list of known hosts.
   Last login: Wed Sep 23 11:10:58 2020


   Welcome to 4.19.90-2003.4.0.0036.oe1.aarch64

   System information as of time:  Thu Nov 26 06:44:18 CST 2020

   System load:    0.83
   Processes:      107
   Memory used:    6.1%
   Swap used:      0.0%
   Usage On:       89%
   IP address:     172.18.156.13
   Users online:   1



   root@vm-2p8g ~#
   ```

   For more information about how to use the **submit** command, testbox options, and how to borrow the specified operating system, see the FAQ at the end of this document.

4. Return the test machine (VM) after use.

   ```shell
   root@vm-2p8g ~# reboot
   Connection to 172.168.131.2 closed by remote host.
   Connection to 172.168.131.2 closed.
   hi684@account-vm ~/lkp-tests/jobs%
   ```

# Applying for a Test Machine (Physical Machine)

1. Generate a local RSA private-public key pair.

   ```shell
   hi684@account-vm ~% ssh-keygen -t rsa
   Generating public/private rsa key pair.
   Enter file in which to save the key (/home/hi684/.ssh/id_rsa):
   Created directory '/home/hi684/.ssh'.
   Enter passphrase (empty for no passphrase):
   Enter same passphrase again:
   Your identification has been saved in /home/hi684/.ssh/id_rsa.
   Your public key has been saved in /home/hi684/.ssh/id_rsa.pub.
   The key fingerprint is:
   SHA256:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx hi684@account-vm
   The key's randomart image is:
   +---[RSA 2048]----+
   |xxxxxxxxxxxxxxxxx|
   |xxxxxxxxxxxxxxxxx|
   |xxxxxxxxxxxxxxxxx|
   |xxxxxxxxxxxxxxxxx|
   |xxxxxxxxxxxxxxxxx|
   |xxxxxxxxxxxxxxxxx|
   |xxxxxxxxxxxxxxxxx|
   |xxxxxxxxxxxxxxxxx|
   |xxxxxxxxxxxxxxxxx|
   +----[SHA256]-----+
   hi684@account-vm ~% ls -hla .ssh
   total 16K
   drwx------. 2 hi684 hi684 4.0K Nov 26 16:37 .
   drwx------. 7 hi684 hi684 4.0K Nov 26 16:37 ..
   -rw-------. 1 hi684 hi684 1.8K Nov 26 16:37 id_rsa
   -rw-r--r--. 1 hi684 hi684  398 Nov 26 16:37 id_rsa.pub
   ```

2. Select the YAML file as required.

   A **lkp-tests** folder is stored in each user directory `/home/${USER}`.

   ```shell
   hi684@account-vm ~% cd lkp-tests/jobs
   hi684@account-vm ~/lkp-tests/jobs% ls -hl borrow-*
   -rw-r--r--. 1 root root  53 Nov  2 14:54 borrow-10d.yaml
   -rw-r--r--. 1 root root  64 Nov  2 14:54 borrow-1d.yaml
   -rw-r--r--. 1 root root 235 Nov 19 15:27 borrow-1h.yaml
   ```

3. Submit the YAML file and connect to the test machine (physical machine).

   ```shell
   hi684@account-vm ~/lkp-tests/jobs% submit -c -m testbox=taishan200-2280-2s64p-256g borrow-1h.yaml
   submit borrow-1h.yaml, got job_id=z9.170594
   query=>{"job_id":["z9.170594"]}
   connect to ws://172.168.131.2:11310/filter
   {"job_id":"z9.170594","message":"","job_state":"submit","result_root":"/srv/result/borrow/2020-11-26/taishan200-2280-2s64p-256g/openeuler-20.03-aarch64/3600/z9.170594"}
   {"job_id": "z9.170594", "result_root": "/srv/result/borrow/2020-11-26/taishan200-2280-2s64p-256g/openeuler-20.03-aarch64/3600/z9.170594", "job_state": "set result root"}
   {"job_id": "z9.170594", "job_state": "boot"}
   {"job_id": "z9.170594", "job_state": "download"}
   {"time":"2020-11-26 14:51:56","mac":"84-46-fe-26-d3-47","ip":"172.168.178.48","job_id":"z9.170594","state":"running","testbox":"taishan200-2280-2s64p-256g--a5"}
   {"job_state":"running","job_id":"z9.170594"}
   {"job_id": "z9.170594", "state": "set ssh port", "ssh_port": "50420", "tbox_name": "taishan200-2280-2s64p-256g--a5"}
   Host 172.168.131.2 not found in /home/hi684/.ssh/known_hosts
   Warning: Permanently added '[172.168.131.2]:50420' (ECDSA) to the list of known hosts.
   Last login: Wed Sep 23 11:10:58 2020


   Welcome to 4.19.90-2003.4.0.0036.oe1.aarch64

   System information as of time:  Thu Nov 26 14:51:59 CST 2020

   System load:    1.31
   Processes:      1020
   Memory used:    5.1%
   Swap used:      0.0%
   Usage On:       3%
   IP address:     172.168.178.48
   Users online:   1



   root@taishan200-2280-2s64p-256g--a5 ~#
   ```

   For more information about how to use the **submit** command, testbox options, and how to borrow the specified operating system, see the FAQ at the end of this document.

4. Return the test machine (physical machine) after use.

   ```shell
   root@taishan200-2280-2s64p-256g--a5 ~# reboot
   Connection to 172.168.131.2 closed by remote host.
   Connection to 172.168.131.2 closed.
   hi684@account-vm ~/lkp-tests/jobs%
   ```

# FAQ

* How Do I Change the Duration of Keeping the Test Machine when Applying for It?

  ```shell
  hi684@account-vm ~/lkp-tests/jobs% cat borrow-1h.yaml
  suite: borrow
  testcase: borrow

  ssh_pub_key: <%=
   begin
   File.read("#{ENV['HOME']}/.ssh/id_rsa.pub").chomp
   rescue
   nil
   end
   %>
  sshd:
  # sleep at the bottom
  sleep: 1h
  hi684@account-vm ~/lkp-tests/jobs% grep sleep: borrow-1h.yaml
  sleep: 1h
  # Use the VIM editor to change the value of the sleep field.
  hi684@account-vm ~/lkp-tests/jobs% vim borrow-1h.yaml
  # After changing the value, submit the request again.
  hi684@account-vm ~/lkp-tests/jobs% submit -c -m testbox=vm-2p8g borrow-1h.yaml
  ```

* Guide to the **submit** Command

  Reference: [submit-job.md](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/submit-job.en.md)

* What Are the testbox Options?

  For details about the testbox options, visit https://gitee.com/wu_fengguang/lab-z9/tree/master/hosts.

  > ![](./../public_sys-resources/icon-note.gif) **Note**
  >
  > VM testbox: vm-xxx
  >
  > PM testbox: taishan200-2280-xxx

  > ![](./../public_sys-resources/icon-notice.gif) **Notice**
  >
> - If the testbox of a physical machine ends with `--axx`, a physical machine is specified. If a task is already in the task queue of the physical machine, the borrow task you submitted will not be processed until the previous task in the queue is completed.
  > - If the testbox of a physical machine does not end with `-axx`, no physical machine is specified. In this case, the borrow task you submitted will be immediately allocated to idle physical machines in the cluster for execution.

* How Do I Borrow the Specified Operating System?

  For details about the supported `os`, `os_arch`, and `os_version`, see [os-os\_verison-os\_arch.md](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/job/os-os_verison-os_arch.md).
