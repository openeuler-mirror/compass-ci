Feature: queue client

    Background: default user has logged in server
        Given lkp server is ready
        And user "centos" has logged in

    Scenario: add job to queue
        When user "centos" use "lkp queue jobs/myjobs.yaml" to add job
        Then the lkp server echo add job status

    Scenario: user queue job result
        When user "centos" use "lkp queue jobs/myjobs.yaml" to add job
        And user "centos" use "lkp result jobs/myjobs.yaml" to queue job result
        Then the lkp server echo queue job result
