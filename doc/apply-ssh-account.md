
# apply for ssh account

## purpose

The ssh account is used to login our jumper VM, where you can
- submit a job
- ssh into a testbox

## steps overview
1. send email to apply for ssh account
   If approved, you'll get a response email with:

     login command:
       ssh -p port account@server_ip

2. login authentication
   - use pub key
   - use password (if no pub key)

3. submit jobs
   - prepare job.yaml
   - run job
     - command:
       submit job.yaml

## example apply email

        To: team@crystal.ci
        Subject: apply ssh account

        # Show a commit URL that you contributed to an OSS project
        # We'll validate whether the URL contains your email. 
        # for example,
        commit: https://github.com/torvalds/linux/commit/7be74942f184fdfba34ddd19a0d995deb34d4a03

        # attach your ssh pub key as file (optionally but highly recommended)
