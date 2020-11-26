# apply account

## steps
1. send apply account email
   - send apply account email to: compass-ci@qq.com
     attention:
       email subject:
         apply account
       email body:
         example:
           my oss commit: https://github.com/torvalds/linux/commit/7be74942f184fdfba34ddd19a0d995deb34d4a03
       attachment:
         ssh pubkey file

   - email example:

        To: compass-ci@qq.com
        Subject: apply account

        # Show a commit URL that you contributed to an OSS project
        # We'll validate whether the URL contains your email. 
        # for example,
        my oss commit: https://github.com/torvalds/linux/commit/7be74942f184fdfba34ddd19a0d995deb34d4a03
        # attach your ssh pub key to the email as attachment
 
2. receive email from compass-ci@qq.com
   the email contains following information:
     - my_email
     - my_name
     - my_uuid
     - SCHED_HOST
     - SCHED_PORT

3. local environment configuration
   follow steps in the email to finish the following configuration
   - setup default yaml
       ~/.config/compass-ci/default/account.yaml

for more information: how to use submit 
  https://gitee.com/openeuler/compass-ci/blob/master/doc/compass-ci测试平台使用教程--submit命令详解.md
