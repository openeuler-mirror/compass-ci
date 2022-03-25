# 外网邮箱收发邮件配置

为了实现和外网用户进行邮件交流，需在linux服务器上对邮箱进行接受/发送邮件配置。
完成配置后，将自动同步邮件到Linux服务器，同时，在使用mutt发送邮件时，默认发件人将使用配置的外网邮件地址。

## 准备工作

### 安装依赖包

使用root帐号或sudo权限，执行下面命令安装收/发邮件所需的依赖包：

        yum -y install cyrus-sasl-plain procmail fetchmail

### 授权定时任务

每次服务器重启都需要自动启动接收邮件的进程，从而实现实时邮件同步。、
最直接的方式就是crontab添加开机运行的定时任务，实现这个功能需要先将要添加定时任务的用户添加到/ec/cron.allow。

### mutt 全局配置

使用root用户，配置：
  - 重新设置用户邮箱的简写别名到compass-ci.org。
  - 重新设置别名为all的邮件地址为:

        compass-ci@openeuler.org。

    在发送邮件给all时，将发送给所有订阅了compass-ci@openeuler.org的邮件地址。


### 邮箱配置

添加订阅邮件

  访问下面的网页完成邮件订阅：

        https://mailweb.openeuler.org/postorius/lists/compass-ci.openeuler.org/

  它将发送一封完成订阅的确认邮件，直接恢复邮件以完成订阅，或忽略邮件取消订阅。


  开启邮箱的以下服务：

        - IMAP/SMTP
        - POP/SMTP

  对于腾讯企业邮箱，可参考官方配置: 

        https://open.work.weixin.qq.com/help?person_id=0&doc_id=302&helpType=exmail

  生成“授权秘密”，该密码将在配置收发邮件时用到。
  腾通讯企业邮箱需先进行微信绑定，再生成客户端密码，具体操作可参考官方配置：

        https://open.work.weixin.qq.com/help?person_id=0&doc_id=301&helpType=exmail

### 用户主目录创建‘$HOME/.email-info’文件

执行mutt-setup-mail脚本进行配置前需要先添加‘.email-info’文件，在用户主目录下创建该文件。

.email-info文件内容如下：

---
        # 根据自己的邮箱添加以下行
        EMAIL_ADDR=zhangsan@compass-ci.org
        EMAIL_PASS={{ email passwd }}
        EMAIL_NAME="Zhang San"

        # smtp_url 的格式如下：
        #
        #       smtp://email_address@smpt_server_address:port
        #
        # email_address里的‘@’前添加转义字符'\'.
        # 对于有些邮箱，比如腾讯企业邮箱，用'smpts://'替代'smpt://'.
        EMAIL_SMTP_URL="smtps://zhangsan\@compass-ci.org@smtp.exmail.qq.com:465"

        # 根据本地实际邮件目录配置MAIL_DIR
        MAIL_DIR="~/Maildir"

        # 指定mailbox名，如果该目录已存在，则指定一个新的名字
        MAIL_BOX="pubbox"
---

## 一键完成配置

执行下面命令完成邮箱配置：
        mutt-setup-mail $HOME/.email-info
