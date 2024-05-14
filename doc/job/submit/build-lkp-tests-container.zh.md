# 前言

为了适应在各个版本的Linux操作系统上运行，我们提供了lkp-tests的容器化解决方案。
你无需在您的本地服务上安装lkp-tests，也将避免缺乏依赖包而导致的安装失败。

# 前置准备

    请在您的本地服务器上完成下面步骤：

        - 安装docker
        - 申请账号并配置默认的yaml文件
        - 生成本地的公私钥

# 构建容器

## 1. 下载资源

    本地下载lkp-tests和compass-ci

    下载资源：

        git clone https://gitee.com/openeuler/compass-ci.git
        git clone https://gitee.com/compass-ci/lkp-tests.git

## 2. 添加环境变量

    配置环境变量：

        echo "export LKP_SRC=$PWD/lkp-tests" >> ~/.${SHELL##*/}rc
        echo "export CCI_SRC=$PWD/compass-ci" >> ~/.${SHELL##*/}rc
        source ~/.${SHELL##*/}rc

## 3. 构建镜像

    镜像构建：

        cd compass-ci/container/submit
        ./build

## 4. 添加可执行文件

    创建可执行文件：

        ln -s $CCI_SRC/container/submit/submit /usr/bin/submit

# 开始第一个任务

    说明：

        和在你的本地服务器上安装lkp-tests一样，您可以直接使用‘submit’命令提交任务。
        每一个任务都会生成一个一次性的容器来执行。
        可执行文件submit会将您下载的lkp-tests挂载到容器内的lkp-tests路径上，这样您在本地编辑lkp-tests文件，在容器内也会生效。
        


    提交任务命令示例：


        submit -c -m testbox=vm-2p8g borrow-1h.yaml

    submit命令：

        了解更多submit命令的使用方法，请参考：[submit用户手册](https://gitee.com/openeuler/compass-ci/blob/master/doc/job/submit/submit-job.zh.md)
