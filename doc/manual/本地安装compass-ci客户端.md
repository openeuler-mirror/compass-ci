# 本地安装compass-ci客户端

Compass-CI 将 [lkp-tests](https://gitee.com/wu_fengguang/lkp-tests) 作为客户端，通过本地安装 lkp-tests 可以手动提交测试任务

:exclamation: 前提条件：按照 [apply-ssh-account.md](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/apply-account.md) 完成如下动作：
- send apply account email
- receive email from compass-ci@qq.com

## Getting started

1. setup default config

    run the following command to add the below setup to default config file
```SHELL
    mkdir -p ~/.config/compass-ci/defaults/
    cat >> ~/.config/compass-ci/defaults/${USER}.yaml <<-EOF
        my_uuid: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxx
        my_email: xxx
        my_name: xx
    EOF
```
2. download lkp-tests and dependencies

    run the following command to install the lkp-test and effect the configuration
```SHELL
    git clone https://gitee.com/wu_fengguang/lkp-tests.git
    cd lkp-tests
    make install
    source ~/.bashrc && source ~/.bash_profile
```
3. submit job

    Now try [submitting a job to compass-ci](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/submit命令详解.md)
