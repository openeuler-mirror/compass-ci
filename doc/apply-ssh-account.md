
# apply for jumper account

## purpose

The jumper account is used to login the jumper VM, where you can
- submit a job
- ssh into a testbox
- read output of the job

## steps overview
### manually assign account
for internal user
1. run assign account tool
   usage:
     answerback-mail.rb [-e|--email email] [-s|--ssh-pubkey pub_key_file] [-f|--raw-email email_file] [-g|--gen-sshkey]

   login command:
     ssh -p port account@server_ip

2. login authentication
   - use pub key
   - use password (if no pub key)

3. submit jobs
   - prepare job.yaml
   - submit job
     - command:
       submit job.yaml

### apply account with email
for external user
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
 
2. successfully applied account email
   it will return an email with following information:
     - my_email
     - my_name
     - my_uuid
     - SCHED_HOST
     - SCHED_PORT

3. environment configuration
   follow steps in the email to finish the following configuration
   - setup default yaml
       ~/.config/compass-ci/default/account.yaml
   - download and install lkp-tests
   - prepare to submit jobs
