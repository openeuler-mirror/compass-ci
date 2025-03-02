# included from both ruby and crystal

# EXECUTION-DOMAIN STAGES
# Job stages proceed in order, it's normal to skip some stage.
# On any health problem, job_health and last_success_stage will be set, and
# job_stage directly set to "finish", which is the final stage all jobs will
# eventually settle down at.
JOB_STAGE_NAME2ID = {
  "submit"       =>  0,
  "dispatch"     =>  1,
  "boot"         =>  2,
  "setup"        =>  3,
  "wait_peer"    =>  4,
  "running"      =>  5,
  "post_run"     =>  6,   # test script run to end
  "manual_check" =>  7,   # interactive user login
  "renew"        =>  8,   # extended borrow time for interactive user login
  "finish"       =>  9,   # to release testbox resource
  "cancel"       => 10,   # cancel by user before running. No start, so no finish.
  "abort_wait"   => 11,   # auto cancel by scheduler, due to abort_wait
}

# DATA-DOMAIN STAGES
# data uploading starts after
# - "post_run" stage, if testbox itself has networking and can upload via curl
# - "finish" stage, by the qemu/docker provider, if testbox UPLOAD_BY_COPY_TO host shared dir
# so data may or may not be ready after "finish" stage.
JOB_DATA_READINESS_NAME2ID = {
  "N/A"           =>  0,
  "uploading"     =>  1,
  "uploaded"      =>  2,
  "complete"      =>  3,  # stats available
  "incomplete"    =>  4,  # stats may be incomplete, user space bisect should skip
  "norun"         =>  5,  # cancled, no run, no stats. this state is necessary for wakeup mechanism
  # check_wait_spec() assumes id order: complete < incomplete/cancel
}

# order is not important
JOB_HEALTH_NAME2ID = {
  "unknown"                       =>  0,

  # complete run, exit code indicates either success or fail
  "success"                       =>  1,
  "fail"                          =>  2,    # test script non-zero exit code

  # no run, no data
  "cancel"                        =>  10,   # cancel by user

  # booted up, pre-condition not met
  "wget_kernel_fail"              =>  20,
  "wget_initrd_fail"              =>  21,
  "initrd_broken"                 =>  22,
  "load_disk_fail"                =>  23,
  "error_mount"                   =>  24,
  "microcode_mismatch"            =>  25,

  "abort_wait"                    =>  30,   # abort due to any waited job failure
  "abort"                         =>  31,   # pre-condition not met, test script cannot continue

  # user-space tests may be incomplete
  "soft_timeout"                  =>  40,
  "nfs_hang"                      =>  41,
  "oom"                           =>  42,   # Out Of Memory
  "kernel_panic"                  =>  43,   # detected kernel panic, maybe force reboot

  "terminate"                     =>  44,   # terminate by user (force kill/reboot machine)
  "disturbed"                     =>  45,   # disturbed by user interactive login

   # somehow blocked, so rebooted by lifecycle terminate_timeout_jobs()
  "timeout_dispatch"              =>  50,
  "timeout_boot"                  =>  51,
  "timeout_setup"                 =>  52,
  "timeout_wait_peer"             =>  53,
  "timeout_running"               =>  54,
  "timeout_post_run"              =>  55,
  "timeout_manual_check"          =>  56,
  "timeout_renew"                 =>  57,
}

JOB_STAGE_ID2NAME = JOB_STAGE_NAME2ID.invert
JOB_HEALTH_ID2NAME = JOB_HEALTH_NAME2ID.invert
JOB_DATA_READINESS_ID2NAME = JOB_DATA_READINESS_NAME2ID.invert

# these are suitable as direct fields
# - read frequently: common/useful in end user query
# - write once: won't change after initial submit
MANTI_STRING_FIELDS = %w[suite category my_account testbox arch osv]

# these can be in-place updated at low cost
MANTI_INT64_FIELDS = %w[submit_time boot_time running_time finish_time]
MANTI_INT32_FIELDS = %w[boot_seconds run_seconds istage ihealth]

# their k=v will be added to full_text_kv for fast MATCH query
# MANTI_STRING_FIELDS will be added too
MANTI_FULLTEXT_FIELDS = %w[
    tbox_type build_type spec_file_name
    queue all_params_md5 pp_params_md5 tbox_group hostname
    host_machine group_id os os_version
    pr_merge_reference_name job_stage job_health
    last_success_stage os_project package build_id os_variant
]
MANTI_FULLTEXT_ARRAY_FIELDS = %w[
    target_machines
]

# for auto substitution in query input/output
MANTI_JSON_PROPERTIES = MANTI_FULLTEXT_FIELDS + MANTI_FULLTEXT_ARRAY_FIELDS
