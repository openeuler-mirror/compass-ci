使用compass-ci平台测试开源仓库，需要完成
1. 将仓库url添加到upstream-repos仓库中
2. 添加自己的测试case

### 首先，将想要测试的代码仓信息以yaml格式文件的形式添加到upstream-repos仓库

仓库地址为：https://gitee.com/wu_fengguang/upstream-repos

你可以先fork这个仓库，新建文件之后，通过Pull Request的方式完成添加。

以仓库backlight为例：

它的url为：https://github.com/baskerville/backlight
1. 以首字母和仓库名创建路径
```
mkdir -p b/backlight
```
2. 在该目录下新建同名文件backlight：
```
cd b/backlight
touch backlight
```
3. 使用vim写入url：
```
vim backlight
```
内容格式为
```
---
url:
- https://github.com/baskerville/backlight
```
请保持格式一致，若不确定，可参考upstream-repos仓库中已有文件。

### 然后，将测试case以yaml文件的形式添加到lkp-tests仓库的jobs目录

仓库地址为 https://gitee.com/wu_fengguang/lkp-tests

这其中有一些已经适配好的测试case，如果你想要测试的case其中正好有，那就可以直接使用。使用方式以iperf为例。

iperf是已经适配的一个测试case，在lkp-tests仓库的jobs下有一个iperf.yaml文件，里面有一些测试的基本参数。

然后，你要在compass-ci仓库下面的 sbin/auto_submit.yaml 文件中添加
```
b/backlight/backlight:
- testbox=vm-2p8g os=openEuler os_version=20.03 os_mount=initramfs os_arch=aarch64 iperf.yaml
```
并通过Pull Request的方式提交。相关参数含义见参考文档

参考文档：
- [compass-ci测试平台使用教程--submit命令详解](https://gitee.com/wu_fengguang/compass-ci/tree/master/doc)
- [如何适配测试用例](https://gitee.com/wu_fengguang/lkp-tests/blob/master/doc/add-testcase.md)

