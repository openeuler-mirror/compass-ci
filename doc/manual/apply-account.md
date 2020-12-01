# apply account

## step 1: send email to apply account

Email template:

---
	From: {{ David Rientjes <rientjes@google.com> }}
	To: compass-ci@qq.com
	Subject: apply account

	my oss commit: {{ https://github.com/torvalds/linux/commit/7be74942f184fdfba34ddd19a0d995deb34d4a03 }}

	{{ attach your ssh pubkey file(s), e.g. ~/.ssh/id_rsa.pub }}

---

- please replace the 3 parts in {{ }} with your information.
- my oss commit: a git commit URL that has your contribution.

## step 2: receive an email

Which contains account information for you:

	- my_email
	- my_name
	- my_uuid
	- SCHED_HOST
	- SCHED_PORT

## step 3: one-time setup

Follow the email to setup your local environment:

	- clone git repos
	- write ~/.config/compass-ci/default/account.yaml

## step 4: try it out

Now try [submitting a job to compass-ci](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/submit命令详解.md)