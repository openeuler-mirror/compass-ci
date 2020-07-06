Feature: Scheduler

  # use API: "/submit_job", "/set_host_mac"
  #   "/boot.ipxe/mac/$mac" "/job_initrd_tmpfs/$id/job.cgz"
  Scenario: submit basic iperf job and consume from API boot.ipxe/mac/$mac
    Given prepared a job "right_iperf.yaml"
    When call with API: post "submit_job" job from add_job.sh
    Then return with job id
    When call with API: put "set_host_mac" "vm-hi1620-2p8g-chief => ef:01:02:03:04:05"
    And call with API: get "boot.ipxe/mac/ef:01:02:03:04:05"
    Then return with basic ipxe boot parameter and initrd and kernel

  # more API need test (group as a scenario) :
  #   "/job_initrd_tmpfs/$id/job.cgz"
  #   "/~lkp/cgi-bin/lkp-jobfile-append-var"
  #   "/~lkp/cgi-bin/lkp-post-run"

  # and more job to test :
  #   which will call no covered code
