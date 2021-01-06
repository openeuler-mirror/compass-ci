# SPDX-License-Identifier: MulanPSL-2.0+

# email monitor robot

## purpose

apply account/uuid for user
  uuid: used for user to submit jobs
  account: used for user to check the test data

## usage

build email as the following section: allowed email format
send mail to: compass-ci-robot@qq.com

## allowed email format:

subject: apply account
mail content
  my oss commit: commit_url
  example:
    my oss commit: https://github.com/torvalds/aalinux/commit/7be74942f184fdfba34ddd19a0d995deb34d4a03
attahcment
  ssh pub_key

## steps overview

1. mail-robot
     monitor_new_email
     - the monitor will listen to the mailbox for new email files
       handle_new_email:
         read email file content
         apply_account
           invoke AssignAccount for new account

2. apply-account
   init my_info
     - my_email
     - my_name
   check_to_send_account
     - parse_mail_content
       invoke ParseApplyAccountEmail
         parse_commit_url
           extract_commit_url
             check whether there is a standard commit url
           base_url_in_upstream_repos
             check whether the repo's url in upstream-repos
           commit_url_availability
             check whether the commit url valid
             - gitee_commit
               clone the repo and check the commit
             - non_gitee_commit(url)
               check the commit with curl

         parse_pub_key
           check whether there has an attachment file to the email file
             attachment:
               first attachment

     - apply_my_account
         my_token
           generate uuid
         apply_account
           invoke ApplyJumperAccount to apply new account with my_info and pub_key
             my_info:
               - my_name
               - my_email
               - my_token
             apply_jumper_account
               required data: pub_key
         complete my_info
           my_info add:
             - my_login_name
             - my_commit_url
         store my_info
           invoke es to store the apply infos

     - rescue error
         error type:
           - no commit url
           - commit url not in upstream-repos
           - commit url not available
           - no pub_key
           - no more available account
         build_error_email with raised error message

     - send_mail
         - build success email
         - build failed email
       send mail

3. continue the monitor
     continue to monitor the mailbox for new email file
     cycle run step 1 and 2 if matched email files

4. service log
     use the following command to get the logs
       docker logs -f --tail=100 fluentd | grep mail-robot
