# 账号申请

首先您需要一个账号，可以用来提交job，同时跟踪您的资源消费情况。
因为目前我们的测试机资源池有限，因此需要做一些使用限制。

我们为平台测试所覆盖的开源软件（OSS）的贡献者提供了免费的账号。
你可以通过在下面邮件中提供‘my_oss_commit’来验明正身您是一个开源软件（OSS）的贡献者。

我们同时也为我们的合作者提供了免费的账号。
这种情况需要提供用的邮件，名字，ssh公钥，以及申请测试机的目的。

## 1. 发送邮件进行账号申请

邮件模板：

---
        发件人: {{ David Rientjes <rientjes@google.com> }}
        收件人: compass-ci-robot@qq.com
        邮件标题: apply account

	my_name: {{ David Rientjes }}
	my_account: {{ rientjes }}
	my_purpose: {{ purpose for applying account }}
	my_college: {{ your college }}
	my_company: {{ your company }}
	my_gitee_account: {{ your gitee account }}
	my_oss_commit: {{ https://github.com/torvalds/linux/commit/7be74942f184fdfba34ddd19a0d995deb34d4a03 }}

        {{ 将您的ssh公钥添加为邮件附件，例如 ~/.ssh/id_rsa.pub }}

---

- 使用您的信息替换{{ }}中的内容，并删除’{{ }}’
- my_account 和 my_purpose 是必填项，其他参数可选择添加。
- 邮件名应该使用英文/中文拼音，例如模板中的“David Rientjes”
- my_account 应该使用英文/中文拼音，可以和数字，‘-’，‘_'组合，不可以有空格
- my_oss_commit:  使用您的邮件和名字提交的代码的地址。


  您的仓库需要在平台测试覆盖的范围内，并且注册到：
  [upstream-repos](https://gitee.com/wu_fengguang/upstream-repos).
  如果贡献的OSS工程仓库不在upstream-repos中，请参考：
  [test-oss-project](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/features/test-service/test-oss-project.zh.md)
  将仓库注册到compass-ci测试池中。

## 2. 接收邮件

申请邮件成功后，您将收到反馈邮件，邮件内容包括以下信息：

        my_name
        my_email
        my_token
        lab

## 3. 一次性配置

根据步骤2收到邮件的提示，配置您的本地环境：

        git clone https://gitee.com/wu_fengguang/lkp-tests.git
        setup ~/.config/compass-ci/defaults/account.yaml
              ~/.config/compass-ci/include/lab/{{ lab }}.yaml

## 4. 现在开始

[安装cci客户端](https://gitee.com/openeuler/compass-ci/blob/master/doc/user-guide/install-cci-client.md)
[提交job到compass-ci](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/job/submit/submit-job.en.md)

