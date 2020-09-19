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














// xiezheng, xuejiao
  2. 建立本地环境（构建一个能够提交job的环境）
       
       git clone lkp-tests # submit
       git clone lab-z9    # jobs
       #git clone compass-ci
       
       需要支持linux / windows/mac/ 
       













// liping
  3. 在Crystal-CI中注册自己的仓库
     - ***TODO----------------------------------------注册方式***
     git clone upstream-repos
     add repo
     commit and send patch email or PULL REQUEST
    













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














// yinsi
- 本地搭建compass-ci 服务器节点
  read code: sparrow

## todo call for Cooperation
  improve git bisect 
  improve 数据分析
  improve 数据结果可视化


