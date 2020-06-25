Feature: Scheduler

  Scenario: API submit_job, return with job id
    Given prepared a job "right_iperf.yaml"
    When call with API: post "submit_job" job
    Then return with job id
