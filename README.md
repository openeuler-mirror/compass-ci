## Compass-CI


### 关于Compass-CI

Compass-CI 是一个可持续集成的软件平台。为开发者提供针对上游开源软件（来自 Github, Gitee, Gitlab 等托管平台）的测试服务、登录服务、故障辅助定界服务和基于历史数据的分析服务--。Compass-CI 基于开源软件PR进行自动化测试(包括构建测试，软件包自带用例测试等)，共同构建一个开放、完整的开源软件生态测试系统。


### 功能介绍 

- **测试服务**

使用Compass-CI 基于开源软件 PR 触发[自动化测试](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/%E5%A6%82%E4%BD%95%E4%BD%BF%E7%94%A8compass-ci%E6%B5%8B%E8%AF%95%E5%BC%80%E6%BA%90%E9%A1%B9%E7%9B%AE.md)或[手动提交测试job](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/submit%E5%91%BD%E4%BB%A4%E8%AF%A6%E8%A7%A3.md)。
	
- **调测环境登录**

使用 SSH [登录测试环境进行调测](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/%E5%A6%82%E4%BD%95%E7%94%B3%E8%AF%B7%E6%B5%8B%E8%AF%95%E6%9C%BA.md)。

- **测试结果分析**

通过 [Web](https://compass-ci.openeuler.org) 接口，对历史测试结果进行分析和比较。

- **测试结果复现**

Compass-CI 把测试过程中的各项环境参数保存在任务结果输出的job.yaml文件中，开发者可以通过重新提交job.yaml复现测试结果。

- **辅助定位**

Compass-CI 可以识别自动化构建测试过程中的错误，触发基于 git tree 的测试，找出引入问题的commit。

## Getting started

- **自动化测试**

1. 添加待测试仓库 URL 到 [upstream-repos](https://gitee.com/wu_fengguang/upstream-repos.git) 仓库，[编写测试用例并添加到仓库](https://gitee.com/wu_fengguang/lkp-tests/blob/master/doc/add-testcase.md), 详细流程请查看[这篇文档](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/%E5%A6%82%E4%BD%95%E4%BD%BF%E7%94%A8compass-ci%E6%B5%8B%E8%AF%95%E5%BC%80%E6%BA%90%E9%A1%B9%E7%9B%AE.md)。

2. git push 更新仓库，自动触发测试。

3. 在网页中搜索并查看结果 web: https://compass-ci.openeuler.org/jobs

- **手动提交测试任务**

1. [安装Compass-CI客户端](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/%E6%9C%AC%E5%9C%B0%E5%AE%89%E8%A3%85compass-ci%E5%AE%A2%E6%88%B7%E7%AB%AF.md)
2. [编写测试用例](https/blob/master/doc/add-testcase.md), [手动提交测试任务](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/submit%E5%91%BD%E4%BB%A4%E8%AF%A6%E8%A7%A3.md)
3. 在网页中搜索并查看结果 web: https://compass-ci.openeuler.org/jobs

## Contributing to Compass-CI

我们非常欢迎有新的贡献者，我们也很乐意为我们的贡献者提供一些指导，Compass-CI 主要是使用 Ruby 和 Crystal 开发的一个项目，我们使用 rubocop和 ameba 来规范我d的代码风格，具体说明可以查看 [rococop源码仓](https://github.com/rubocop-hq/rubocop)和[ameba源码仓](https://github.com/crystal-ameba/ameba)。

## Website

所有的测试结果，已加入的开源软件清单，历史测试查询比较都可以在我们的官网 [Website](https://compass-ci.openeuler.org) 上找到。

## 加入我们

您可以通过以下的方式加入我们：
  - 您可以加入我们的 [mailing list](https://mailweb.openeuler.org/postorius/lists/compass-ci.openeuler.org/)
  - 您可以加入我们每周四下午四点 16：00 的项目例会 （会议链接将会通过邮件发送给您）

欢迎您跟我们一起：
  - 增强 git bisect 能力
  - 增强数据分析能力
  - 增强数据结果可视化能力
