## Compass-CI                                                                         


### 关于 Compass-CI

Compass-CI 是一个可持续集成的开源软件平台。为开发者提供针对上游开源软件（来自 Github, Gitee, Gitlab 等托管平台）的测试服务、登录服务、故障辅助定界服务和基于历史数据的分析服务。Compass-CI 基于开源软件 PR 进行自动化测试(包括构建测试，软件包自带用例测试等)，构建一个开放、完整的测试系统。


### 功能介绍 

**测试服务**

Compass-CI 监控很多开源软件 git repos，一旦检测到代码更新，会自动触发[自动化测试](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/test-oss-project.zh.md)，开发者也可以[手动提交测试 job](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/submit-job.zh.md)。
	
**调测环境登录**

使用 SSH [登录测试环境进行调测](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/log-in-machine-debug.md)。

**测试结果分析**

通过 [Web](https://compass-ci.openeuler.org) 接口，对历史测试结果进行分析和比较。

**测试结果复现**

一次测试运行的所有决定性参数会在 job.yaml 文件中保留完整记录。
重新提交该 job.yaml 即可在一样的软硬件环境下，重跑同一测试。

**辅助定位**

如果出现新的 error id，就会自动触发bisect，定位引入该 error id 的 commit。

## Getting started

**自动化测试**

1. 添加待测试仓库 URL 到 [upstream-repos](https://gitee.com/wu_fengguang/upstream-repos.git) 仓库，[编写测试用例](https://gitee.com/wu_fengguang/lkp-tests/blob/master/doc/add-testcase.md)并添加到 [lkp-tests](https://gitee.com/wu_fengguang/lkp-tests) 仓库, 详细流程请查看[这篇文档](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/test-oss-project.zh.md)。

2. 执行 git push 命令更新仓库，自动触发测试。

3. 在网页中[查看](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/browse-results.zh.md)和[比较](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/compare-results.zh.md)测试结果 web: https://compass-ci.openeuler.org/jobs
   
**手动提交测试任务**

1. [安装 Compass-CI 客户端](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/install-cci-client.md)。
2. [编写测试用例](https://gitee.com/wu_fengguang/lkp-tests/blob/master/doc/add-testcase.md), [手动提交测试任务](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/submit-job.zh.md)。
3. 在网页中[查看](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/browse-results.zh.md)和[比较](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/compare-results.zh.md)测试结果 web: https://compass-ci.openeuler.org/jobs

**登录测试环境**

1. 向 compass-ci-robot@qq.com 发送邮件[申请账号](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/apply-account.md)。
2. 根据邮件反馈内容完成环境配置。
3. 在测试任务中添加 sshd 字段，提交相应的任务，[登录测试环境](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/log-in-machine-debug.md)。

## Contributing to Compass-CI

我们非常欢迎有新的贡献者，我们也很乐意为我们的贡献者提供一些指导，Compass-CI 主要是使用 Ruby 开发的一个项目，我们遵循 [Ruby 社区代码风格](https://ruby-china.org/wiki/coding-style)。如果您想参与社区并为 Compass-CI 项目做出贡献，[这个页面](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/learning-resources.md)将会提供给您更多信息，包括 Compass-CI 所使用的所有语言和工具等。

## Website

所有的测试结果，已加入 Compass-CI 平台的开源软件清单，历史测试结果比较都可以在我们的官网 [Website](https://compass-ci.openeuler.org) 上找到。

## 加入我们

您可以通过以下的方式加入我们：
  - 您可以加入我们的 [mailing list](https://mailweb.openeuler.org/postorius/lists/compass-ci.openeuler.org/)

欢迎您跟我们一起：
  - 增强 git bisect 能力
  - 增强数据分析能力
  - 增强数据结果可视化能力
