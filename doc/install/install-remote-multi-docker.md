# deploy remote docker test environment

以docker为测试机，远程hw/vm作为docker的宿主机。在hw/vm上部署multi-docker，接受中心调度器任务分配。

## 申请帐号

1. :exclamation: 前提条件：按照 [apply-account.md](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/account/apply-account.md) 完成如下动作：
- send apply account email
- receive email from compass-ci-robot@qq.com
- get reply email and follow its instructions to
- setup default config

2. additional modification of the scheduler port:
```SHELL
	cat > ~/.config/compass-ci/defaults/root.yaml <<EOF
	SCHED_PORT: 20014
	EOF
```

## 安装multi-docker

```SHELL
	curl https://api.compass-ci.openeuler.org:20006/pub/remote/install-multi-docker.sh | bash

```

## submit job

Now try [submitting a job to compass-ci](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/job/submit/submit-job.zh.md)

提交任务时指定queue为部署multi-docker的主机名，这样提交的测试任务就以该机器为宿主机运行。
示例命令如下:
```SHELL
submit -m  rpmbuild.yaml queue=${HOSTNAME}
```
