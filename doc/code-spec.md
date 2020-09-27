code注意事项
============

- 代码应当放进函数里 不要在脚本顶层直接写逻辑
- 代码应当放进lib/里 脚本本身最小化, 仅解析命令行参数, 调用lib/入口函数
- 如果出现了全局变量 一般意味着需要写一个 class/module 来放这个状态量了
- 一个函数, 不要超过10行代码
- 起准确和有意义的变量/函数名字, 名字要让人看出赋予他们的确切意义

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
