class Sched

  # Shared data structures
  @hw_ipmi_processes = {} of String => Process
  @hw_serial_log_channels = {} of String => Channel(String)
  @hw_serial_login_channels = {} of String => Channel(String)
  @hw_jobid = {} of String => Int64
  @hw_jobfile = {} of String => File?
  @log_rotators = {} of String => String

  START_PATTERNS = [
    "BIOS boot completed.",
    "Booting Linux on physical CPU",
    "Linux version ",
  ]

  END_PATTERNS = [
    "Restarting system",
    "reboot: Power down",
    "sysrq: Resetting",
  ]

  OOPS_PATTERNS = [
    "Kernel panic - not syncing:",
    "NULL pointer dereference",
    "Unable to handle kernel ",
    "BUG: unable to handle page fault"
  ]

  private def setup_serial_consoles
    @hosts_cache.hosts.each do |hostname, _|
      setup_serial_console_for_host(hostname)
    end
  end

  private def setup_serial_console_for_host(hostname)
    return unless info = @hosts_cache[hostname]?
    return unless ipmi_ip = info.hash_str["ipmi_ip"]?

    remove_serial_console_for_host(hostname) # Cleanup existing

    ipmi_user = Sched.options.ipmi_user
    ipmi_password = Sched.options.ipmi_password

    @hw_serial_log_channels[hostname] = Channel(String).new
    @hw_serial_login_channels[hostname] = Channel(String).new

    spawn start_ipmi_session(hostname, ipmi_ip, ipmi_user, ipmi_password)
    spawn process_host_logs(hostname)
  end

  private def remove_serial_console_for_host(hostname)
    if process = @hw_ipmi_processes[hostname]?
      process.signal(:kill) rescue nil
      @hw_ipmi_processes.delete(hostname)
    end

    @hw_serial_log_channels.delete(hostname)
    @hw_serial_login_channels.delete(hostname)
    @hw_jobid.delete(hostname)
    @hw_jobfile.delete(hostname)

    # Cleanup any existing SOL session
    if @hosts_cache.hosts.has_key? hostname
        ipmi_run(hostname, %w(sol deactivate))
    end
  end

  private def start_ipmi_session(hostname, ipmi_ip, ipmi_user, ipmi_password)
    start_time = Time.utc
    loop do
      begin
        # Deactivate first
        Process.run("ipmitool", ["-I", "lanplus", "-H", ipmi_ip, "-U", ipmi_user, "-E", "sol", "deactivate"],
          env: {"IPMI_PASSWORD" => ipmi_password})
        sleep 3.seconds

        # Start SOL session
        start_time = Time.utc
        process = Process.new("ipmitool", ["-I", "lanplus", "-H", ipmi_ip, "-U", ipmi_user, "-E", "sol", "activate"],
          input: :pipe, output: :pipe, error: :pipe,
          env: {"IPMI_PASSWORD" => ipmi_password})

        @hw_ipmi_processes[hostname] = process

        # Handle output
        spawn handle_ipmi_output(process.output, hostname)
        spawn handle_ipmi_input(process.input, hostname)

        process.wait
      rescue e

        log "IPMI error for #{hostname}: #{e}"
        sleep 1.minute
      ensure
        # When IPMI fails fast like this, sleep for long time.
        # [-- Console up -- Sun Feb  9 12:31:03 2025]
        # Error: Unable to establish IPMI v2 / RMCP+ session
        # Error: Unable to establish IPMI v2 / RMCP+ session
        # [-- Console down -- Sun Feb  9 12:31:06 2025]
        # [-- Console up -- Sun Feb  9 12:31:07 2025]
        # Error: Unable to establish IPMI v2 / RMCP+ session
        # Error: Unable to establish IPMI v2 / RMCP+ session
        # [-- Console down -- Sun Feb  9 12:31:10 2025]
        if (Time.utc - start_time) < 10.seconds
          sleep 1.hour
        else
          sleep 1.seconds
        end

        @hw_ipmi_processes.delete(hostname)
      end
    end
  end

  private def log_to_host_file(hostname, line)
    time = Time.utc
    month_dir = time.to_s("%Y-%m")
    log_dir = File.join("#{BASE_DIR}/scheduler/serial", hostname, month_dir)

    daily_file = File.join(log_dir, "#{time.to_s("%Y-%m-%d")}.log")

    # Rotate logs daily
    if @log_rotators[hostname]? != daily_file
      @log_rotators[hostname] = daily_file

      Dir.mkdir_p(log_dir)
      # Create/update current.log symlink
      current_link = File.join("#{BASE_DIR}/scheduler/serial", hostname, "current.log")
      File.delete(current_link) if File.symlink?(current_link)
      File.symlink(daily_file, current_link)

      cleanup_old_logs(hostname)
    end

    File.write(daily_file, line, mode: "a")
  end

  private def cleanup_old_logs(hostname)
    base_dir = File.join("#{BASE_DIR}/scheduler/serial", hostname)
    cutoff = Time.utc - 365.days

    Dir.glob(File.join(base_dir, "????-??/????-??-??.log")).each do |path|
      # Delete old log files
      file_date = File.basename(path, ".log")
      if Time.parse(file_date, "%Y-%m-%d", Time::Location::UTC) < cutoff
        File.delete(path)
      end
    rescue
      # Ignore errors
    end
  end

  private def handle_ipmi_output(output, hostname)
    while line = output.gets
      @hw_serial_log_channels[hostname].send(line)
    end
  end

  private def handle_ipmi_input(input, hostname)
    while command = @hw_serial_login_channels[hostname].receive
      input << command
      input.flush
    end
  end

  private def process_host_logs(hostname)
    channel = @hw_serial_log_channels[hostname]
    loop do
      line = channel.receive

      # Feature 2: Per-host logging
      log_to_host_file(hostname, line)

      # Feature 3: Job logging
      process_job_log(hostname, line)

      # Features 4 & 5: Client notifications
      notify_clients(hostname, line)

      # Feature 6: Crash detection
      check_system_health(hostname, line)
    end
  end

  private def process_job_log(hostname, line)
    jobid = @hosts_cache[hostname].job_id
    return unless job = @jobs_cache[jobid]?

    if @hw_jobid[hostname]? != jobid
      @hw_jobid[hostname] = jobid
      if file = @hw_jobfile[hostname]?
        file.close
        @hw_jobfile.delete hostname
      end
    end

    unless @hw_jobid[hostname]?
      START_PATTERNS.each do |pattern|
        if line.includes?(pattern)
          return unless job.result_root
          log_path = File.join(job.result_root, "dmesg")
          @hw_jobfile[hostname] = File.open(log_path, "a")
          break
        end
      end
    end

    # Write lively to file
    if file = @hw_jobfile[hostname]?
      file.puts(line)
    end

    END_PATTERNS.each do |pattern|
      if line.includes?(pattern)
        @hw_jobfile[hostname].try(&.close)
        @hw_jobfile.delete hostname
        break
      end
    end
  end

  private def notify_clients(hostname, line)
    job_id = @hosts_cache[hostname].job_id

    # Feature 4: Watchlog clients
    if sids = @watchlog_jobid2client_sids[job_id]?
      sids.each do |sid|
        @client_sessions[sid]?.try &.send(line)
      end
    end

    # Feature 5: Console clients
    if sid = @console_jobid2client_sid[job_id]?
      @client_sessions[sid]?.try &.send(line)
    end
  end

  private def check_system_health(hostname, line)
    OOPS_PATTERNS.each do |pattern|
      next unless line.includes?(pattern)
      next unless ipmi_reboot(hostname)
      job_id = @hosts_cache[hostname].job_id
      if job = @jobs_cache[job_id]?
        if JOB_STAGE_NAME2ID[job.job_stage] < JOB_STAGE_NAME2ID["finish"]
          job.job_stage = "incomplete"
          job.job_health = "kernel_panic"
          on_job_update(job_id)
        end
      end
      break
    end
  end

  def ipmi_reboot(hostname)
    ipmi_run(hostname, %w(power reset))
  end

  private def ipmi_run(hostname, params)
    return unless ipmi_ip = @hosts_cache[hostname].hash_str["ipmi_ip"]?
    ipmi_user = Sched.options.ipmi_user
    ipmi_password = Sched.options.ipmi_password

    common_params = ["-I", "lanplus", "-H", ipmi_ip, "-U", ipmi_user, "-E"]
    Process.run("ipmitool", common_params.concat(params),
                env: {"IPMI_PASSWORD" => ipmi_password})
  end

end
