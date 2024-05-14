##  Compass-CI

### About Compass-CI

Compass-CI is an open-source software platform supporting continuous integration. It provides developers with test, login, assistant fault demarcation, and historical data-based analysis services for upstream open-source software (from Github, Gitee, GitLab, and other hosting platforms). Compass-CI performs automatic tests (including the build tests and the use case tests included in software packages) based on the open-source software PR to build an open and complete test system.

### Features

**Test Service**

Compass-CI monitors Git repositories of many open-source software. Once a code update is detected, Compass-CI automatically triggers the [automated test](https://gitee.com/openeuler/compass-ci/blob/master/doc/test-guide/test-oss-project.en.md). Developers can also [manually submit for test](https://gitee.com/openeuler/compass-ci/blob/master/doc/job/submit/submit-job.en.md).

**Logging In to the Commissioning Environment**

Using SSH to [log in to the test environment for commissioning](https://gitee.com/openeuler/compass-ci/blob/master/doc/user-guide/log-in-machine-debug.md)

**Test Result Analysis**

Analyze and compare historical test results through the [Web](https://compass-ci.openeuler.org/) interface.

**Test Result Reproduction**

All deterministic parameters for test running are recorded in the job.yaml file. Submit the job.yaml file again to run the same test in the same software and hardware environments.

**Error Locating**

If a new error ID is generated, the bisect is automatically triggered to locate the commit that introduces the error ID.

## Getting Started

**Automated Test**

1. Add the URL of the repository to be tested to the [upstream-repos](https://gitee.com/compass-ci/upstream-repos.git) repository. [Compiling test cases](https://gitee.com/compass-ci/lkp-tests/blob/master/doc/add-testcase.md) and add the URL to the [lkp-tests](https://gitee.com/compass-ci/lkp-tests) repository. For details, see [this document](https://gitee.com/openeuler/compass-ci/blob/master/doc/test-guide/test-oss-project.en.md).
2. Run the git push command to update the repository. The test is automatically triggered.
3. On the web page, click [view](https://gitee.com/openeuler/compass-ci/blob/master/doc/result/browse-results.en.md) and [compare](https://gitee.com/openeuler/compass-ci/blob/master/doc/result/compare-results.en.md) to view the test result. (web: <https://compass-ci.openeuler.org/jobs>)

**Automatic Test Example**

How can I automatically test my repository <https://github.com/baskerville/backlight> on Compass-CI?

1. Fork upstream-repos repository (https://gitee.com/compass-ci/upstream-repos) and git clone it to the local host.

2. Create the **b/backlight/backlight** file. The file content is as follows:

   ```
   ---
   url:
   - https://github.com/baskerville/backlight
   ```

3. Add test case

   You can compile test cases and add them to the **lkp-tests** repository.

   You can also use the existing test cases in the jobs directory of the lkp-tests repository (<https://gitee.com/compass-ci/lkp-tests>).

   Add the **DEFAULTS** file to the directory where the backlight file is stored and add the configuration information.

   ```
   submit:
   - command: testbox=vm-2p16g os=openeuler os_version=20.03 os_mount=cifs os_arch=aarch64 api-avx2neon.yaml
     branches:
     - master
     - next
   - command: testbox=vm-2p16g os=openeuler os_version=20.03 os_mount=cifs os_arch=aarch64 other-avx2neon.yaml
     branches:
     - branch_name_a
     - branch_name_b
   ```

4. Submit a PR to add the new file to the upstream-repos repository.

**Manually Submitting a Test Task**

1. [Install the compass-ci client.](https://gitee.com/openeuler/compass-ci/blob/master/doc/user-guide/install-cci-client.md)
2. [Compile test cases](https://gitee.com/compass-ci/lkp-tests/blob/master/doc/add-testcase.md) then [manually submit a test task.](https://gitee.com/openeuler/compass-ci/blob/master/doc/job/submit/submit-job.zh.md)
3. On the [web page](https://compass-ci.openeuler.org/jobs), click [view](https://gitee.com/openeuler/compass-ci/blob/master/doc/result/browse-results.zh.md) and [compare](https://gitee.com/openeuler/compass-ci/blob/master/doc/result/compare-results.zh.md) to view the test result.

**Example**

1. The Compass-CI client has been installed following the procedure in [Install the compass-ci client](https://gitee.com/openeuler/compass-ci/blob/master/doc/user-guide/install-cci-client.md) ).

2. Submit the test in a YAML file. You need to prepare the YAML file of the test task in advance.

   You can directly use the existing test cases in the **jobs** directory of the **lkp-tests** repository (<https://gitee.com/compass-ci/lkp-tests>).

   The following uses **iperf.yaml** as an example:

   ```
   suite: iperf
   category: benchmark
   
   runtime: 300s
   
   cluster: cs-localhost
   
   if role server:
     iperf-server:
   
   if role client:
     iperf:
       protocol:
       - tcp
       - udp
   ```

3. Run the submit command to submit the **iperf.yaml** test task.

   ```
   hi8109@account-vm ~% submit iperf.yaml testbox=vm-2p8g
   submit iperf.yaml, got job_id=z9.173924
   submit iperf.yaml, got job_id=z9.173925
   ```

**Logging in to the Test Environment**

1. Send an email to [compass-ci-robot@qq.com](mailto:compass-ci-robot@qq.com) to [apply for an account](https://gitee.com/openeuler/compass-ci/blob/master/doc/user-guide/apply-account.md).
2. Complete the environment configuration based on the email feedback.
3. Add the sshd field to the test task and submit the corresponding task. [Log in to the test environment](https://gitee.com/openeuler/compass-ci/blob/master/doc/user-guide/log-in-machine-debug.md).

**Example**

The test case is **spinlock.yaml**. If a submitted test case fails to be executed, how do I log in to the executor to perform commissioning?

```
suite: spinlock
category: benchmark
nr_threads:
- 1
spinlock:
```

1. To log in to the executor before running the spinlock test script, modify the YAML file as follows:

   ```
   suite: spinlock
   category: benchmark
   nr_threads:
   - 1
   
   ssh_pub_key: <%= File.read("#{ENV['HOME']}/.ssh/id_rsa.pub").chomp rescue nil %>
   sshd:
   runtime: 1h
   sleep:
   
   spinlock:
   ```

   **ssh_pub_key**: Carries the local pub_key for password-free login.

   **sshd**: Indicates that the executor needs to run the lkp-tests/damon/sshd script to establish an SSHR reverse tunnel for SSH login.

   **runtime**: sleep time

   **sleep**: Placed before spinlock, indicating that the spinlock script is executed one hour after sleep.

2. To log in to the executor after the spinlock test fails, modify the YAML file as follows:

   ```
   suite: spinlock
   category: benchmark
   nr_threads:
   - 1
   spinlock:
   
   on_fail:
       sshd:
       sleep: 1h
   ```

   **on_fail**: The test case is executed after the test case fails to be executed.

3. Run the **submit -m -c spinlock.yaml** command to submit the modified YAML file.

   After the SSHD tunnel is established, the PC automatically connects to the executor.

   ```
   hi8109@account-vm ~% submit -m -c spinlock.yaml
   submit_id=6f2d11df-2198-41e9-a0e6-6aa67f9b46e2
   submit spinlock.yaml, got job id=z9.10155176
   query=>{"job_id":["z9.10155176"]}
   connect to ws://api.compass-ci.openeuler.org:20001/filter
   {"level_num":2,"level":"INFO","time":"2021-09-17T17:21:03.436+0800","from":"172.17.0.1:40014","message":"access_record","status_code":200,"method":"GET","resource":"/job_initrd_tmpfs/z9.10155176/job.cgz","job_id":"z9.10155176","job_state":"download","api":"job_initrd_tmpfs","elapsed_time":0.465723,"elapsed":"465.72µs"}
   
   The dc-8g testbox is starting. Please wait about 30 seconds
   {"level_num":2,"level":"INFO","time":"2021-09-17T17:21:08+0800","mac":"02-42-ac-11-00-03","ip":"","job_id":"z9.10155176","state":"running","testbox":"dc-8g.taishan200-2280-2s48p-256g--a67-14","status_code":200,"method":"GET","resource":"/~lkp/cgi-bin/lkp-wtmp?tbox_name=dc-8g.taishan200-2280-2s48p-256g--a67-14&tbox_state=running&mac=02-42-ac-11-00-03&ip=&job_id=z9.10155176","api":"lkp-wtmp","elapsed_time":19.024787,"elapsed":"19.02ms"}
   {"level_num":2,"level":"INFO","time":"2021-09-17T17:21:12.622+0800","from":"172.17.0.1:42838","message":"access_record","status_code":200,"method":"GET","resource":"/~lkp/cgi-bin/lkp-jobfile-append-var?job_file=/lkp/scheduled/job.yaml&job_id=z9.10155176&job_state=running","job_id":"z9.10155176","api":"lkp-jobfile-append-var","elapsed_time":74.76464,"elapsed":"74.76ms","job_state":"running","job_stage":"running"}
   {"level_num":2,"level":"INFO","time":"2021-09-17T17:21:12.982+0800","tbox_name":"dc-8g.taishan200-2280-2s48p-256g--a67-14","job_id":"z9.10155176","ssh_port":"21063","message":"","state":"set ssh port","status_code":200,"method":"POST","resource":"/~lkp/cgi-bin/report_ssh_info","api":"report_ssh_info","elapsed_time":0.414042,"elapsed":"414.04µs"}
   ssh root@172.168.131.2 -p 21063 -o StrictHostKeyChecking=no -o LogLevel=error
   root@dc-8g.compass-ci.net ~#
   ```

## Contributing to Compass-CI

We welcome new contributors, and we are happy to provide guidance to our contributors. Compass-CI is mainly a project developed using Ruby, and we follow the [Ruby Community Code Style](https://ruby-china.org/wiki/coding-style). If you want to participate in the community and contribute to the Compass-CI project, [this page](https://gitee.com/openeuler/compass-ci/blob/master/doc/development/learning-resources.md) will provide you with more information, including all languages and tools used by Compass-CI.

## Website

All test results have been added to the open-source software list of the Compass-CI platform. Historical test results can be found on the [official website](https://compass-ci.openeuler.org/).

## Joining Us

You can join us by subscribing our [mailing list](https://mailweb.openeuler.org/postorius/lists/compass-ci.openeuler.org/).

Welcome to join us to improve:

- The git bisect capability.
- The data analysis capability.
- The data result visualization capability.

## Learn More

[Learn more](./doc/)
