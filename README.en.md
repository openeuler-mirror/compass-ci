## Compass-CI

### Overview

Compass-CI is a software platform supporting continuous integration. It provides developers with a wide range of services for upstream open source software from hosting platforms, such as GitHub, Gitee, and GitLab. These services include test, login, fault demarcation, and historical data analytics. Compass-CI performs automated tests based on the open source software PR, including tests of build and cases provided by software packages. Compass-CI and projects submitted by developers form an open and complete test system.

### Functions

**Test Service**

Compass-CI monitors git repos of a large amount of open source software. Once Compass-CI detects code update, it automatically triggers [automated tests](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/test-oss-project.en.md), and developers can also [manually submit test jobs](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/submit-job.en.md).

**Login to the Test Environment**

The SSH is used to [log in to the test environment for commissioning](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/%E5%A6%82%E4%BD%95%E7%99%BB%E5%BD%95%E6%B5%8B%E8%AF%95%E6%9C%BA%E8%B0%83%E6%B5%8B%E4%BB%BB%E5%8A%A1.md).

**Test Result Analysis**

The historical test results are analyzed and compared using the Web interface.

**Test Result Reproduction**

All deterministic parameters for a test are recorded in the **job.yaml** file. You can submit the **job.yaml** file again to run the same test in the same hardware and software environments.

**Error Locating**

If a new error ID is generated, the bisect is automatically triggered to locate the commit of the error ID.

## Getting Started

**Performing an Automated Test**

1. Add the URL of the repository to be tested to the [upstream-repos](https://gitee.com/wu_fengguang/upstream-repos.git), [compile test cases](https://gitee.com/wu_fengguang/lkp-tests/blob/master/doc/add-testcase.md), and [add them to the repository](https://gitee.com/wu_fengguang/lkp-tests). For details, see [this document](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/test-oss-project.en.md).

2. Run the **git push** command to update the repository and automatically trigger the test.

3. You can [view](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/browse-results.en.md) and [compare](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/compare-results.en.md) test results on the web page: https://compass-ci.openeuler.org/jobs

**Manually Submitting a Test Task**

1. [Install the Compass-CI client](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/%E6%9C%AC%E5%9C%B0%E5%AE%89%E8%A3%85compass-ci%E5%AE%A2%E6%88%B7%E7%AB%AF.md).
2. [Compile test cases and manually submit test tasks](https://gitee.com/wu_fengguang/lkp-tests/blob/master/doc/add-testcase.md).
3. You can [view](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/browse-results.en.md) and [compare](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/compare-results.en.md) test results on the web page: https://compass-ci.openeuler.org/jobs

**Logging in to the Test Environment**

1. Send an email to the compass-ci-robot@qq.com to [apply for an account](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/apply-account.md).
2. [Complete the environment configuration](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/%E6%9C%AC%E5%9C%B0%E5%AE%89%E8%A3%85compass-ci%E5%AE%A2%E6%88%B7%E7%AB%AF.md) as instructed by the email.
3. Add the **sshd** field to the test task, submit the task, and [log in to the test environment](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/%E5%A6%82%E4%BD%95%E7%99%BB%E5%BD%95%E6%B5%8B%E8%AF%95%E6%9C%BA%E8%B0%83%E6%B5%8B%E4%BB%BB%E5%8A%A1.md).

## Contributing to Compass-CI

We are glad to have new contributors and provide them with guidance. Compass-CI is a project developed using Ruby, and the project follows the [Ruby Code Style](https://ruby-china.org/wiki/coding-style). If you want to join the community and contribute to the Compass-CI project, [this page](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/learning-resources.md) will provide you with more information, including all the languages and tools used by Compass-CI.

## Website

All test results, the list of open source software that has been added to Compass-CI, and historical test result comparisons can be found on our [official website](https://compass-ci.openeuler.org).

## Joining Us

You can join us by

- Joining our [mailing list](https://mailweb.openeuler.org/postorius/lists/compass-ci.openeuler.org/)

Together, we can enhance the capabilities of

- git bisect
- Data analytics
- Data analytics result visualization
