# 连接 lab-z9 和 crystal

## 一、生成 ssh 公私钥

1、打开 Windows PowerShell

方式一：通过开始菜单打开。点击开始按钮，在搜索栏中输入 "PowerShell" ，在搜索结果中选择 "Windows PowerShell" 。

方式二：通过运行窗口打开。按下 Win+R 组合键打开运行窗口，输入 "powershell" 并点击 "确定" 按钮。

2、通过 ssh-keygen -t rsa -m PEM -b 2048 命令生成 ssh 公私钥。

输入要保存秘钥文件的路径和名称，直接敲击回车键生成 .ssh 文件夹并保存至此。

输入密码，直接敲击回车键选择不设置密码。

确认密码，直接敲击回车键选择不设置密码。

## 二、将公钥内容插入authorized_keys文件

1、连接到远程主机登录 z9 账号

2、通过 vim ~/.ssh/authorized_keys 命令打开 authorized_keys 文件

3、将生成的公钥 id_rsa.pub 的内容插入，保存并退出

注意：公钥 id_rsa.pub 的内容插入后不能断行

4、crystal 操作同上

## 三、黄区：jumper 直连 z9 / crystal

1、创建新链接，访问类型选择 "Linux 命令行" ，填写连接信息
- z9
  ```
  ip: 123.60.114.28
  port: 32002
  ```
- crystal
  ```
  ip: 123.60.114.27
  port: 22113
  ```

2、填写用户名，将生成的私钥 id_rsa 的内容粘贴到私钥位置，保存后就能直连 z9 / crystal。

注意：私钥 id_rsa 的内容中 "-----BEGIN RSA PRIVATE KEY-----" 和 "-----END RSA PRIVATE KEY-----" 部分也需复制粘贴

## 四、蓝区：远程直连 z9 / crystal

**远程工具可自行选取，此处使用 NxShell 作为示例**

1、新建会话，填写连接信息（同黄区连接第一步）

2、认证方式选择 "私钥" ，填写登录用户名，私钥选择生成的 id_rsa 文件，保存后就能直连 z9 / crystal。
