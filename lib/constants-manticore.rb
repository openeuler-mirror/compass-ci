# included from both ruby and crystal

# final stage will stop at: complete / incomplete
# check_wait_spec() assumes id order: complete < incomplete
JOB_STAGE_NAME2ID = {
  "submit"       =>  1,
  "download"     =>  2,
  "boot"         =>  3,
  "running"      =>  4,
  "post_run"     =>  5,
  "uploading"    =>  6,
  "finish"       =>  7,   # test script run to end
  "manual_check" =>  8,   # interactive user login
  "renew"        =>  9,   # extended borrow time for interactive user login
  "complete"     =>  10,  # stats available&valid
  "incomplete"   =>  11,  # no valid stats, bisect should skip
}

# order is not important
JOB_HEALTH_NAME2ID = {
  "success"             =>  1,
  "fail"                =>  2,    # test script non-zero exit code
  "abort"               =>  3,    # pre-condition not met, test script cannot continue
  "cancel"              =>  4,    # cancel by user
  "terminate"           =>  5,    # terminate by user (force kill/reboot machine)
  "oom"                 =>  6,    # Out Of Memory
  "kernel_panic"        =>  7,    # detected kernel panic, maybe force reboot
  "wget_kernel_fail"    =>  8,
  "wget_initrd_fail"    =>  9,
  "load_disk_fail"      =>  10,
  "initrd_broken"       =>  11,
  "soft_timeout"        =>  12,
  "nfs_hang"            =>  13,
  "mount_fs_fail"       =>  14,
  "microcode_mismatch"  =>  15,
  "error_mount"         =>  16,
  "disturbed"           =>  17,
  "timeout_download"    =>  18,   # set by lifecycle terminate_timeout_jobs()
  "timeout_boot"        =>  19,
  "timeout_running"     =>  20,
  "timeout_post_run"    =>  21,
  "timeout_uploading"   =>  22,
}

JOB_STAGE_ID2NAME = JOB_STAGE_NAME2ID.invert
JOB_HEALTH_ID2NAME = JOB_HEALTH_NAME2ID.invert

# these are suitable as direct fields
# - read frequently: common/useful in end user query
# - write once: won't change after initial submit
MANTI_STRING_FIELDS = %w[suite category my_account testbox arch osv]

# these can be in-place updated at low cost
MANTI_INT64_FIELDS = %w[id submit_time boot_time running_time finish_time]
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
