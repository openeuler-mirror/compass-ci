# Prepare

- Apply account
- Config default yaml files

If you have not completed above works, reference to [apply-account.md](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/user-guide/apply-account.md) to finish it.

# Apply testbox

## 1. Generate local ssh pub key

    Use the command below to check the pub key exists:

        ls ~/.ssh/*.pub

    Generate one if you don't have one now:

        ssh-keygen

## 2. Select the job yaml

    We have provided various examples for you in dir ~/lkp-tests/jobs:

    You can filtrate examples for borrowing machine with command below:

        cd ~/lkp-tests/jobs
        ls borrow*

## 3. Submit job

    Command to submit jobs:

    for DCs:

        submit -c -m testbox=dc-2g os_mount=container docker_image=centos:8 borrow-1h.yaml

    for VMs:

        submit -c -m testbox=vm-2p8g borrow-1h.yaml

    for HWs:

        submit -c -m testbox=taishan200-2280-2s48p-256g borrow-1h.yaml

    - You can view the logs in real time for the job with the command above。
    - You will directly login the testbox if the job runs successfully.
    - And you will receive an email that contains login command and server configuration information.
    - Only within the period of borrowing machine, you can access the textbox with the login command.

## 4. renew testbox
    Login testbox to renew the lease, before testbox expires.
    get testbox lease:
        lkp-renew -g
    renew N days:
        lkp-renew Nd

## 5. Return testbox

    Return manually(recommended):

        Manually execute 'reboot' in time to return the testbox.
        Avoid a waste of computer resource with no-load running.

    Return automatically on maturity:

        The testbox will be returned automatically if it has expired its service life.

    - All testboxes will be returned if it has been executed command 'reboot'.
    - The testbox cannot be accessed any more after it has been returned.
    - Apply a new one if you want continue to use it.

# FAQ

* Customize the borrowing time

    Find key in the yaml file and edit its value according to your requirement.

	The borrowing period can be calculated in days and hours.
	The maximum period is no more than 10 day.

* Guidance for command submit

    See the usage and options for command 'submit' the command below:

	submit -h

    Reference the following line to learn the advanced usage for command 'submit':
    
    [submit detailed usage](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/job/submit/submit-job.zh.md)

* Available testbox

    For a full list of testbox, reference to https://gitee.com/wu_fengguang/lab-z9/tree/master/hosts

    >![](../icons/icon-note.gif) **instruction:**
    >
    > - DCs: dc-xxx
    > - VMs: vm-xxx
    > - HWs: taishan200-2280-xxx

    >![](../icons/icon-notice.gif) **attention:**
    > - It means that you choosed a specified physical machine if the testbox name is end with `--axx`.
    > - You will need to wait if there are already tasks in the task queue for the machine.
    > - Your job will be randomly assigned to a machine that meets the requirements if the testbox name is not end with '-axx'.

* Specify the OS

    About supportted `os`, `os_arch`, `os_version`, reference to [os-os_verison-os_arch.md](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/job/fields/os-os_verison-os_arch.md)
