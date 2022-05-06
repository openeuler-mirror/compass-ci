WATCH_STATE = {
  "job_health" => {
    "bad" => %w[failed incomplete abnormal timeout crash OOM
                load_disk_fail error_mount wget_kernel_fail
                wget_initrd_fail initrd_broken kexec_fail],
    "good" => ["success"]
  }
}
