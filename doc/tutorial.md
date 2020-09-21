# Crystal-CI Introduction

## 简单说明














//kaitian

  - Crystal-CI是什么？
     > Crystal-CI 是面向广泛的开源软件测试的一个项目，主要的思路是通过对各种上游社区及代码托管平台的开源软件进行编译、构建、开源软件自带用例测试，验证开源软件与操作系统、多样性硬件平台的兼容性。

  - 我们提供什么服务
    >  当前鲲鹏生态刚刚起步，正在广泛建设基础软件来发展鲲鹏生态本项目主要是为了构建面向更广泛的开源软件与openEuler及鲲鹏兼容性，同时也可以为社区开发者提供友好的调测环境，包括环境登录、结果分析、辅助定界能力。



## 快速入门

- 前提条件














// shengde
  1. 如何申请账号
       通过向compass-ci@openeuler.io发邮件申请
       配置default
       write TODO














## 2. 建立本地环境（构建一个能够提交job的环境）
下载lkp-tests, 安装依赖包并配置环境变量
       ```bash
       git clone http://gitee.com/wu_fengguang/lkp-tests.git
       cd lkp-tests
       make install
       ```












## 3. 注册自己的仓库

如果您想在git push的时候, 自动触发测试, 那么需要把您的公开git url添加到如下仓库
[upstream-repos](https://gitee.com/wu_fengguang/upstream-repos)
	git clone https://gitee.com/wu_fengguang/upstream-repos.git
	less upstream-repos/README.md














// yale
  4. 提交测试任务

       1. job yaml文件如何写？（简单介绍并附上示例）
          - ***TODO----------------------------------------***
	  details refer to
	  https://gitee.com/wu_fengguang/lkp-tests/blob/master/jobs/README.md
          
       2. 如何提交yaml文件（job） 我们监控仓库中某个文件夹？or 通过某种方式上传到某个位置？
          - ***TODO----------------------------------------***














// weitao
  5、查看测试结果
  	local: /srv/result/$suite/$testbox/$date/$jobid/ file types under it
        通过job web 直接查看任务结果
        通过命令行查询














// yuhang
  6、比较测试结果
  	concepts
        通过compare web  查询比较结果
        通过命令行查询














// zhengde
  7. 提交borrow任务
	fields:
		sshd:
		runtime:

  	os env
	testbox list
	submit -c -m borrow.yaml














// xueliang
  8. 提交 bisect任务
     - ***TODO----------------------------------------***
    


## 高级功能













// chenglong, yuchuan
- 添加OS支持
  nfs
  osimage














// baijing, zhangyu
- 添加测试用例
 refer to
 https://gitee.com/wu_fengguang/lkp-tests/blob/master/doc/add-testcase.md 














// shaofei
- PKGBUILD 构建 














// wangyong
- depends














- 本地搭建compass-ci 服务器节点

      概述：在openEuler系统一键部署compass-ci环境

      声明：目前已支持 openEuler-aarch64-20.03-LTS 系统环境
            以下配置仅供参考

      - 准备工作

              - 硬件
                      服务器类型：ThaiShan200-2280 (建议)
                            架构：aarch64
                            内存：>= 8GB
                             CPU：64 nuclear       (建议)
                            硬盘：>= 500G

              - 软件
                              OS：openEuler-aarch64-20.03 LTS
                             git：2.23.0版本       (建议)
                        预留空间：>= 300G
                            网络：可以访问互联网

      说明: openEuler系统安装
      https://openeuler.org/zh/docs/20.03_LTS/docs/Installation/%E5%AE%89%E8%A3%85%
E5%87%86%E5%A4%87.html

      - 操作指导

              1. 登录openEuler系统

              2. 创建工作目录并设置文件权限

                      mkdir demo && cd demo && umask 002

              3. 克隆compass-ci项目代码到demo目录

                      git clone https://gitee.com/wu_fengguang/compass-ci.git

              4. 执行一键部署脚本install-tiny

                      cd compass-ci/sparrow && ./install-tiny



## todo call for Cooperation
  improve git bisect 
  improve 数据分析
  improve 数据结果可视化


