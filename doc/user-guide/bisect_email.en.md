# Who are we?

Compass-CI runs a number of tests for open source projects for free.
We aim to improve OSS quality in a number of hardware and OS environment.
We are part of the openEuler community.

# Why do you get the email?

Whenever you git push, our test robot will pull and test the new code.
When new errors are found, Compass-CI will auto run git bisect to find out the first bad commit,
and send email report to the commit author.

# About the email

The first bad commit job result directory:
you can read the below file to understand the content of each file.
- https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/result/browse-results.en.md

Notice:
You may need to read the output file of the first bad commit job result directory,
it is the build log about the first bad commit.

# how to confirm bug fix

- git push your fix patch to your project.
- download the job.yaml from the first bad commit job directory.
- submit -m job.yaml upstream_commit=$your_fix_commit.
- check result from the new result directory which is in output above command and key is result_root.
