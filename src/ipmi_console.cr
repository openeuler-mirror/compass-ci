class Sched

  # Shared data structures
  @hw_ipmi_processes = {} of String => Process
  @hw_serial_log_channels = {} of String => Channel(String)
  @hw_serial_login_channels = {} of String => Channel(String)
  @hw_jobid = {} of String => Int64
  @hw_jobfile = {} of String => File?
  @hw_fifofile = {} of String => File?
  @log_rotators = {} of String => String
  @needs_startup_detection = {} of String => Bool

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
      @hw_fifofile.delete(hostname)
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
        fifo_path = "/tmp/sol_input_#{Process.pid}"
        File.delete(fifo_path) if File.exists?(fifo_path)
        Process.run("mkfifo", [fifo_path])
        # Deactivate first
        Process.run("ipmitool", ["-I", "lanplus", "-H", ipmi_ip, "-U", ipmi_user, "-E", "sol", "deactivate"],
          env: {"IPMI_PASSWORD" => ipmi_password})
        sleep 3.seconds

        # Start SOL session
        start_time = Time.utc
        @hw_ipmi_processes[hostname] = Process.new("sh", ["-c", <<-SHELL],
          script -q -f -c 'ipmitool -I lanplus -H #{ipmi_ip} -U #{ipmi_user} -P #{ipmi_password} sol activate' /dev/null < #{fifo_path}
        SHELL
          output: :pipe,
          error: :pipe
        )
        @hw_fifofile[hostname] = File.open(fifo_path, "w")

        # Handle output
        spawn handle_ipmi_output(hostname)
        spawn handle_ipmi_input(hostname)

        @hw_ipmi_processes[hostname].wait
      rescue e
        pp "IPMI error for #{hostname}: #{e}"
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
        @hw_fifofile.delete(hostname)
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

  private def handle_ipmi_output(hostname)
    begin
      output = @hw_ipmi_processes[hostname].output
      buffer = Bytes.new(4096)
      while (bytes_read = output.read(buffer)) > 0
        @hw_serial_log_channels[hostname].send(String.new(buffer[0, bytes_read]))
      end
    rescue e
      pp e
    end
  end

  private def handle_ipmi_input(hostname)
    while command = @hw_serial_login_channels[hostname].receive
      begin
        fifo = @hw_fifofile[hostname]
        fifo.not_nil!.write(String.new(Base64.decode(command)).to_slice)
        fifo.not_nil!.flush
      rescue e
        pp e.message
      end
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
    @needs_startup_detection ||= {} of String => Bool

    if @hw_jobid[hostname]? != jobid
      @hw_jobid[hostname] = jobid
      if file = @hw_jobfile[hostname]?
        file.close
        @hw_jobfile.delete hostname
      end
      @needs_startup_detection[hostname] = true
    end

    if ! @hw_jobid[hostname]? || @needs_startup_detection[hostname]?
      START_PATTERNS.each do |pattern|
        if line.includes?(pattern)
          client_sid = @console_jobid2client_sid[jobid]?
          if client_sid
            startup_message = {type: "console-startup", job_id: jobid}.to_json
            @client_sessions[client_sid]?.try &.send(startup_message)
            @needs_startup_detection.delete hostname
          end

          return unless job.result_root
          log_path = File.join(BASE_DIR, job.result_root, "console.log")
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
        break unless jobfile = @hw_jobfile[hostname]?
        @hw_jobfile[hostname].try(&.close)
        @hw_jobfile.delete hostname
        break
      end
    end
  end

  private def notify_clients(hostname, line)
    return unless host_info = @hosts_cache[hostname]?

    job_id = @hosts_cache[hostname].job_id

    if sid = @console_jobid2client_sid[job_id]?
      @client_sessions[sid]?.try &.send({"type" => "console-output", "data" => Base64.strict_encode(line.to_slice)}.to_json)
    end
  end

  private def check_system_health(hostname, line)
    OOPS_PATTERNS.each do |pattern|
      next unless line.includes?(pattern)
      code, msg = ipmi_reboot(hostname)
      next unless code == HTTP::Status::OK
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

  private def ipmi_run(hostname : String, params : Array(String))
    # Retrieve IPMI details from the cache
    ipmi_ip = @hosts_cache[hostname].hash_str["ipmi_ip"]?
    unless ipmi_ip
      return HTTP::Status::BAD_REQUEST, "IPMI IP not found for host: #{hostname}"
    end

    # Prepare IPMI command parameters
    ipmi_user = Sched.options.ipmi_user
    ipmi_password = Sched.options.ipmi_password
    common_params = ["-I", "lanplus", "-H", ipmi_ip, "-U", ipmi_user, "-E"]

    # Execute the IPMI command
    status = Process.run("ipmitool", common_params.concat(params), env: {"IPMI_PASSWORD" => ipmi_password})
    unless status.success?
      return HTTP::Status::INTERNAL_SERVER_ERROR, "IPMI command failed: #{status.to_s}"
    end

    return HTTP::Status::OK, "Success"
  end

end
