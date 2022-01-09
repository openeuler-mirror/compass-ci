# 使用 compass-ci 平台测试开源项目

本文介绍了使用 compass-ci 平台测试开源项目的操作。

### 添加待测试仓库 URL 到 upstream-repos 仓库

执行以下步骤，将想要测试的代码仓信息以 yaml 文件的方式添加到 upstream-repos 仓库（https://gitee.com/wu_fengguang/upstream-repos ）。

1. Fork upstream-repos 仓库并 git clone 到本地，本文以 backlight 仓库（https://github.com/baskerville/backlight ）为例说明。

![](../images/fork_backlight.png)

2. 执行以下命令，以首字母和仓库名创建文件路径。

    ```
    mkdir -p b/backlight
    ```

3. 执行以下命令，在该目录下新建同名文件 backlight。
    ```
    cd b/backlight
    touch backlight
    ```

4. 执行以下命令，将 backlight 仓库 url 信息写入 backlight 文件。

    ```
    vim backlight
    ```
    内容格式为

    ```
    ---
    url:
    - https://github.com/baskerville/backlight
    ```

    >![](./../../icons/icon-notice.gif) **注意：**
	>
    >可参考 upstream-repos 仓库中已有文件格式,请保持格式一致。

5. 通过 Pull Request 命令将新增的 backlight 文件提交到 upstream-repos 仓库。


### 提交测试任务到 compass-ci 平台

1. 准备测试用例

    测试用例可以自己编写并添加到 lkp-tests 仓库，也可以直接使用 lkp-tests 仓库（https://gitee.com/wu_fengguang/lkp-tests ）的 jobs 目录下已有的测试用例。

    * 使用仓库中已经适配好的测试用例
	如果 lkp-tests 仓库中正好有你想要的测试用例，你可以直接使用。以 iperf.yaml 文件为例说明如下：
	iperf.yaml 是一个已经适配好的测试用例，它位于 lkp-tests 仓库的 jobs 目录下，其中有一些基本的测试参数。

    * 编写测试用例并添加到仓库

        请参考：[如何添加测试用例](https://gitee.com/wu_fengguang/lkp-tests/blob/master/doc/add-testcase.md )

2. 配置 upstream-repos仓库中的DEFAULTS文件，提交测试任务

    你只需要在上述backlight文件所在目录增加 DEFAULTS 文件并添加配置信息，如：
    ```
    submit:
    - command: testbox=vm-2p16g os=openeuler os_version=20.03 os_mount=cifs os_arch=aarch64 api-avx2neon.yaml
      branches:
      - master
      - next
    - command: testbox=vm-2p16g os=openeuler os_version=20.03 os_mount=cifs os_arch=aarch64 other-avx2neon.yaml
      branches:
      - branch_name_a
      - branch_name_b

    ```
    通过 Pull Request 的方式将修改好的 DEFAULTS 文件提交到 upstream-repos 仓库，就可以使用 compass-ci 测试你的项目了。

    详细配置方式请参考 https://gitee.com/wu_fengguang/upstream-repos/blob/master/README.md 。

    命令参数意义及作用请参考 https://gitee.com/wu_fengguang/compass-ci/tree/master/doc/job 。
