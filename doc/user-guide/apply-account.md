# apply account

WARNING:
	Due to security requirements for the data center, applying account for compass-ci by sending emails is no longer supported.
	To apply for a compass-ci account, please contact:

		shdluan@163.com

	In additional:

		To use compass-ci, you need to log in to the client environment for compass-ci: account-vm
		To log in to account-vm, you need a server, which has static IP and was added to the whitelist of compass-ci environment;
		You need use secret key to log in to the account-vm, support ssh pub key when applying the compass-ci account.

You'll need an account to submit jobs. The account is mainly for tracking your resource consumptions.
We have limited pool of testboxes, so there have to be some usage control.

We offer free accounts to OSS (Open Source Software) contributors where the OSS project is in our test coverage.
You can prove yourself as OSS contributor by providing "my_oss_commit" in the below email.

We offer free accounts to our collaborators too. If you are one of our
collaborators, you should know the collaboration channel to apply account.
In this case you just need provide name, email, ssh pubkey and purpose.

## step 1: send email to apply account

Email template:

---
	From: {{ David Rientjes <rientjes@google.com> }}
	To: compass-ci-robot@qq.com
	Subject: apply account

	my_name: {{ David Rientjes }}
	my_account: {{ rientjes }}
	my_purpose: {{ purpose for applying account }}
	my_college: {{ your college }}
	my_company: {{ your company }}
	my_gitee_account: {{ your gitee account }}
	my_oss_commit: {{ https://github.com/torvalds/linux/commit/7be74942f184fdfba34ddd19a0d995deb34d4a03 }}

	{{ attach your ssh pubkey file(s), e.g. ~/.ssh/id_rsa.pub }}

---

- please replace the parts in {{ }} with your information, no keep the '{{ }}'.

- my_account and my_purpose is required, other items are optional.

- the email name should be in English or Chinese Pinyin, as: "David Rientjes" in the template.

- the my_account should be in English of Chinese Pinyin, and should only contains letters, numbers, '-' or '_'.

- my_oss_commit: a git commit URL that has your name and email.
  The git repo should be in our test coverage and registered in
  [upstream-repos](https://gitee.com/compass-ci/upstream-repos).
  If your contributed OSS project is not in upstream-repos, you may refer to
  [test-oss-project](https://gitee.com/openeuler/compass-ci/blob/master/doc/test-guide/test-oss-project.en.md)
  to add it to compass-ci testing.

## step 2: receive an email

Which contains account information for you:

	my_name
	my_email
	my_token
	lab

## step 3: one-time setup

**Follow instructions in the email** to setup your local environment:

	git clone https://gitee.com/compass-ci/lkp-tests.git
	setup ~/.config/compass-ci/defaults/account.yaml
	      ~/.config/compass-ci/include/lab/{{ lab }}.yaml

## step 4: Now try

[install-cci-client](https://gitee.com/openeuler/compass-ci/blob/master/doc/user-guide/install-cci-client.md)
[submitting a job to compass-ci](https://gitee.com/openeuler/compass-ci/blob/master/doc/job/submit/submit-job.en.md)

