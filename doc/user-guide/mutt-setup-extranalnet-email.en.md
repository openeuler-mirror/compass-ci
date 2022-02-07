# email setup for public network mailbox

Facilitate communicate with extranet users by email, config the mailbox on the linux server for accepting/sending emails.
It will automatically synchronize the email from the server.
And the default sender uses the configured email address when sending emails using mutt.

## prepare works

### install required packages

Use root or sudo permission to install the required packages for sending/fetching emails:

        yum -y install cyrus-sasl-plain procmail fetchmail

### enable scheduled task

Automatically start the fetchmail process is needed to enable fetching mail in real time for per user when the server meets any reboot. 
A easy way to implement it is enable users to add crontab jobs of @reboot.
So use root to add the specified users to file: /etc/cron.allow to allow it.

### common config for mutt

use root to do config:
  - reassign the alias for user's email for compass-ci.org mailbox.
  - reassign the alias all to the subscription email address:

        compass-ci@openeuler.org

    when send emails to all, it will send the email to all the emails that subscribed compass-ci@openeuler.org

### config email

email subscription

  Follow the following url to register the email subscription:

        https://mailweb.openeuler.org/postorius/lists/compass-ci.openeuler.org/

  It will send an email for you to confirm the registration, just reply the email to finish the registration.
  Ignore the email will cancel the registration.


  Enable the following services for the email:

        - IMAP/SMTP
        - POP/SMTP

    The following url will tell how to enable the service for Tencent Enterprise Mailbox：

        https://open.work.weixin.qq.com/help?person_id=0&doc_id=302&helpType=exmail

  Generate a authorization secret and save it. It is needed when configuring sending/fetching email.
  For Tencent Enterprise Mailbox, bind wexin first, and then re-generate a new "Client special password".
  The following url will tell how to bind the weixin and generate a new password:

         https://open.work.weixin.qq.com/help?person_id=0&doc_id=301&helpType=exmail

### local add email info file

An email_info file is required when executing the script: mutt-setup-mail to do the email configuration. Add one at your work directory.

The email-info file content as follows:

---
        # add the following line according to user's own email
        EMAIL_ADDR=zhangsan@compass-ci.org
        EMAIL_PASS={{ email passwd }}
        EMAIL_NAME="Zhang San"

        # the format for smtp_url is as follows:
        #
        #       smtp://email_address@smpt_server_address:port
        #
        # add '\' before the '@' in he email_address part.
        # for some mailbox, like Tencent Enterprise Mailbox, use 'smtps://' instead of 'smtp://'.
        EMAIL_SMTP_URL="smtps://zhangsan\@compass-ci.org@smtp.exmail.qq.com:465"

        # add the following line according to your local mailbox config
        MAIL_DIR="~/Maildir"
        MAIL_BOX=".inbox"
---

## One click to do the email config

run the following command to finish the email config:

        mutt-setup-mail email-info
