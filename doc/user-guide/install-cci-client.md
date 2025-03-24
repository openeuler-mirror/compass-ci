# 本地安装compass-ci客户端

Compass-CI 将 [lkp-tests](https://gitee.com/compass-ci/lkp-tests) 作为客户端，通过本地安装 lkp-tests 可以手动提交测试任务

lkp-tests提交任务依赖ruby，建议安装ruby2.5及以上版本。

## 申请帐号

:exclamation: 前提条件：按照 [apply-account.md](https://gitee.com/openeuler/compass-ci/blob/master/doc/user-guide/apply-account.md) 完成如下动作：
- send apply account email
- receive email from compass-ci-robot@qq.com
- get reply email and follow its instructions to
  - setup default config

## 下载安装 lkp-tests

Run the following command to install/setup lkp-test:

```SHELL
    git clone https://gitee.com/compass-ci/lkp-tests.git
    cd lkp-tests
    make install-depends
    source ~/.${SHELL##*/}rc
```

## submit job

Now try [submitting a job to compass-ci](https://gitee.com/openeuler/compass-ci/blob/master/doc/job/submit/submit-job.zh.md)
