code注意事项
============

- 在开始设计、编码之前，请善用搜索，善于复用现成code。
  大部分基本问题在网上有现成的答案，往往还是最优解。

- 代码应当放进函数里 不要在脚本顶层直接写逻辑

- 代码应当放进lib/里 脚本本身最小化, 仅解析命令行参数, 调用lib/入口函数

- 如果出现了全局变量 一般意味着需要写一个 class/module 来放这个状态量了

- 一个函数, 不要超过10行代码, 该原则适用于所有ruby/crystal/shell各类程序.

- 起准确和有意义的变量/函数名字, 名字要让人看出赋予他们的确切意义

- 函数要有分层结构. 每个函数须有明确的定位: 业务层逻辑, 还是底层支持性routine.
  一个函数不能同时做两个层次的事. 同一函数内避免混杂不同类型的事务.

- 如果注释仅仅是代码的简单重复, 不提供额外信息量, 不要写.

- puts/printf字符串应当容易搜索(grep)。特别注意包含足够长的固定内容substring.
例如：
```SHELL
	die "test yaml\(${test_yaml}\) not exist in ${LKP_SRC}/jobs !!!"
==>
	die "cannot find test yaml ($test_yaml) in $LKP_SRC/jobs"
	     ^^^^^^^^^^^^^^^^^^^^^ grep-friendly fixed substring
```

重构友好编码
============

基本原则:
- 预防自己的代码造成他人的几大困难
  - 难以理解 不敢下手
  - 不知道怎么找到*所有*关联逻辑
  - 不知道自己不知道 (unknown unknown)
- 设想将来做重构, 或者需要理解任何一个高层次的功能/流程,
  一个新人应当可以通过 git grep 一两个关键字或者pattern,
  就能找到所有相关底层代码与文档, 而不必担心有所遗漏.

基本方法:
- 隐式场景显式化: 加注释明确代码的各类隐含目的, 意义, 场景, 数据示例等等
- 隐式依赖显式化: 定义相同的ID, 把所有的关联文档与各处代码串起来
- 分散依赖集中化: 定义类/函数/assert, 封装/强制 各类设计中的假设, 约定与规则

PATCH注意事项
=============

- PATCH title 应当简要说明做了什么 (what)

- PATCH changelog / code comment 应当解释读者无法从代码简单推断的
  - 背景
  - 目的
  - 效果
  - 设计选项和权衡
  - 实际例子
  - 改进数字
  - bug场景, 出错消息原文

- PATCH 应当加上作者签名 (Signed-off-by: Name <email>)

- PATCH 最好不超过100行, 一个PATCH只做一件事, 避免混杂多个逻辑变更

- changelog/comment里的话，需理顺逻辑关系，让人一看就知道在讲什么，
  比如问题、原因、条件、结果、预期、假设、场景、目的、副作用、权衡，
  哪些是因果关系，哪些是可能，哪些是肯定。

- 论述问题的时候，引用必要的代码或output，帮助明确逻辑流/数据流。
  引文加TAB缩进显示。

PATCH格式
=========

## patch title/subject

一般形式为

        area: ...
其中area为模块名、目录、文件名。

如果是bug fix，就写成

        area: fix ...

如果是文档，可以写成

        doc: ...
        doc/file.md: ...

如果是重构，就写成

        area: refactor xxx
        area: simplify xxx

首字母不必大写
勿以'.'结尾

一般别写 "improve ..."
特别别写 "modify ..." 因为这个词没啥信息量。

PATCH参考材料
=============

The patch subject and changelog should be well written according to suggestions
here:

	https://github.com/thoughtbot/dotfiles/blob/master/gitmessage
	https://www.cnblogs.com/cpselvis/p/6423874.html

	http://www.ozlabs.org/~akpm/stuff/tpp.txt
	2: Subject:
	3: Attribution
	4: Changelog

	https://www.kernel.org/doc/html/latest/translations/zh_CN/process/submitting-patches.html#cn-describe-changes
	2) 描述你的改动
	3) 拆分你的改动
	8）回复评审意见

文档与易用性
============

- 每个feature都应当有
  - 用户文档
  - 设计文档
  - 指示对应的代码在哪里(class/func); 或者如果有多处代码互相配合, 指示用什么关键字grep能把它们串起来看

- 每个有命令行参数的脚本, 都应当支持help output (-h|--help|参数不够时 显示帮助信息)
  - dependencies/assumptions
  - input parameters
  - input/output example

接口变更
========
- 变更原则：

  <font color="#4590a3">
    接口的变更会影响用户使用，变更时需要兼容旧的接口功能，过渡期为1年，过渡期结束后可废弃旧功能
  </font>

- 接口变更引发的问题，例如：
  ```
    submit rpmbuild.yaml
    eg rpmbuild.yaml：
      ...
      custom_repo_name: centos7
  ```

  用户提交构建任务时需要指定`custom_repo_name`,
  如用户未指定，那么系统默认赋值：
  ```
  custom_repo_name: openeuler-20.03
  ```
  这样用户构建的结果将上传到默认仓库：`openeuler-20.03`

  如果用户期望将构建结果上传至 `centos7`, 但job.yaml中忘记指定 `custom_repo_name`,
  那么系统结果将不符合用户预期。

  为了避免这样的操作失误:

  我们强制用户提交任务时，在 `rpmbuild.yaml` 中指定 `custom_repo_name`

  但是，像这样的接口变更，导致用户使用旧的 `rpmbuild.yaml` 提交任务失败

  因此，<font color="#4590a3">功能变更一定要平滑过渡</font>

- 通用接口变更流程：
  1. 加入新代码，保留旧代码并确保它们正常工作
  2. 添加warn，提示用户旧功能：xxx 于2023-2-10（1年）后弃用
  3. 在旧功能代码处添加注释，如：
     ```
     //TODO： remove it after 2023-2-10
     < old code >
     ```
  4. 2023-2-10（1年）后删除旧功能对应代码
