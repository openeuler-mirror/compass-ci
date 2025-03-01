
# Represents a WebSocket connection session with type safety
class WebSocketSession
  enum SessionType
    Client
    Provider
  end

  property type : SessionType
  property socket : HTTP::WebSocket
  property env : HTTP::Server::Context
  property sid : Int64
  property created_at : Time = Time.utc

  @@last_sid : Int64 = 0

  def initialize(@type, @socket, @env)
    @sid = @@last_sid
    @@last_sid += 1
  end

  def closed? : Bool
    @socket.closed?
  end

  # Safe message sending with error handling
  def send(message : String) : Bool
    if closed?
      Log.warn { "Cannot send message to closed session #{sid}" }
      return false
    end

    begin
      @socket.send(message)
      return true
    rescue ex : IO::Error
      Log.error(exception: ex) { "Failed to send message to session #{sid}" }
      return false
    end
  end
end

class Sched

  property client_sessions = {} of Int64 => WebSocketSession
  property provider_sessions = {} of String => WebSocketSession

  property console_jobid2client_sid = {} of Int64 => Int64
  property watchlog_jobid2client_sids = {} of Int64 => Array(Int64)
  property watchjob_jobid2client_sids = {} of Int64 => Array(Int64)

  # << hosts write job request to it
  # >> dispatch worker reads them, find job, then
  # - tbox_type = hw: write to hw_machine_channels[host]
  # - tbox_type = vm|dc: write to provider_sessions[host].socket
  @host_request_job_channel = Channel(HostRequest).new
  @hw_machine_channels = {} of String => Channel(JobHash)

  @wait_client_channel = Hash(Int64, Channel(Int64)).new # /scheduler/v1/jobs/wait clientid => Channel(jobid)
  @wait_client_spec = Hash(Int64, HashHHH).new
  @@last_wait_client_id : Int64 = -1_i64

  property jobs_cache = Hash(Int64, JobHash).new

  # on updated job fields, should check this mapping to wake up possible jobs/clients
  # @jobs_wait_on[job.wait_on.keys.each] << job.id64
  # @jobs_wait_on[jobid] << negative clientid
  property jobs_wait_on = Hash(Int64, Set(Int64)).new  # Array(Int64) is waiting for first Int64

  def api_view_job(job_id : Int64, fields : String?)
    job = get_job(job_id)
    return unless job
    job.export_public_fields(fields)
  end

  def get_job(job_id : Int64) : JobHash?
    job = @jobs_cache[job_id]? ||
          @jobs_cache_in_submit[job_id]?
    return job if job

    job = @es.get_job(job_id.to_s)
    add_job_to_cache(job) if job
    job
  end

  def change_job_data_readiness(job, job_data_readiness, do_wakeup : Bool = true)
    job.job_data_readiness = job_data_readiness
    job.idata_readiness = JOB_DATA_READINESS_NAME2ID[job_data_readiness] || -1

    on_job_update(job.id64) if do_wakeup

    if job.idata_readiness == JOB_DATA_READINESS_NAME2ID["uploaded"]
      on_job_data_uploaded(job)
    end

    if job.idata_readiness >= JOB_DATA_READINESS_NAME2ID["complete"]
      job.set_time("complete_time")
      on_job_complete(job)
    else
      job.set_time("#{job_data_readiness}_time")
    end
  end

  def change_job_stage(job, job_stage, health_problem)
    if health_problem
      job.job_health = health_problem
      job.ihealth = JOB_HEALTH_NAME2ID[health_problem] || -1
      job.last_success_stage = job.job_stage
    end

    if job_stage == "cancel"
      change_job_data_readiness(job, "norun", false)
    end

    if job_stage
      job.job_stage = job_stage
      job.istage = JOB_STAGE_NAME2ID[job_stage] || -1
      job.set_time("#{job_stage}_time")

      on_job_update(job.id64)

      # job finished?
      if job.istage >= JOB_STAGE_NAME2ID["finish"]
        on_job_finish(job)
      end
    end
  end

  def on_job_update(cjob_id : Int64)
    return unless @jobs_wait_on.has_key? cjob_id
    return unless cjob = get_job(cjob_id)

    to_remove = [] of Int64
    @jobs_wait_on[cjob_id].each do |id|
      if id >= 0
        # another job is waiting for me
        to_remove << id if handle_job_dependency(id, cjob)
      else
        # a http post "/scheduler/v1/jobs/wait" client is waiting for me
        to_remove << id if handle_client_dependency(id, cjob_id)
      end
    end

    if to_remove.size == @jobs_wait_on[cjob_id].size
      @jobs_wait_on.delete cjob_id
    else
      to_remove.each { |id| @jobs_wait_on[cjob_id].delete id }
    end
  end

  # job finish or abort
  def on_job_finish(job)
    job.set_boot_seconds
    check_retire_job(job)
  end

  def on_job_data_uploaded(job)
    spawn {
      @stats_worker.handle(job)
      change_job_data_readiness(job, "complete")
    }
  end

  # called on 2 data conditions:
  # - complete: job stats created
  # - incomplete: won't change any more
  def on_job_complete(job)
    @es.replace_doc("jobs", job)
    report_workflow_job_event(job.id, job)
    check_retire_job(job)
  end

  def check_retire_job(job)
    return if job.istage < JOB_STAGE_NAME2ID["finish"]
    return if job.idata_readiness < JOB_DATA_READINESS_NAME2ID["complete"]
    @jobs_cache.delete job.id64
  end

  # wjob: waiting job (wait_on cjob)
  # cjob: changed job
  private def handle_job_dependency(wjob_id : Int64, cjob : JobHash)
    dependent_job = get_job(wjob_id)
    # cannot find the job or job info that wait on me,
    # return true to remove it from tracking
    return true unless dependent_job

    wait_spec = dependent_job.hash_hhh
    return true unless wait_spec["wait_on"]?

    progress = check_wait_spec(cjob.id64, wait_spec)

    if progress && !wait_spec.has_key?("wait_on")
      if progress == :fail_fast
        change_job_stage(dependent_job, nil, "abort_wait")
        change_job_data_readiness(dependent_job, "incomplete")
      else
        add_job_to_cache(dependent_job)
      end
    end

    progress
  end

  private def handle_client_dependency(client_id : Int64, cjob_id : Int64)
    client_spec = @wait_client_spec[client_id]?
    return unless client_spec

    if check_wait_spec(cjob_id, client_spec)
      @wait_client_channel[client_id]?.try &.send(cjob_id)
    end
  end

  def check_wait_spec(cjob_id : Int64, wait_spec : HashHHH) : Bool|Symbol
    wait_on = wait_spec["wait_on"]? || return false
    job_id_str = cjob_id.to_s
    return false unless wait_on.has_key?(job_id_str)

    job_spec = wait_on[job_id_str]
    cjob = get_job(cjob_id)
    return false unless cjob

    # if only jobid, the default condition is job complete
    if job_spec.nil? || job_spec.empty?
      return false unless cjob.idata_readiness >= JOB_DATA_READINESS_NAME2ID["complete"]
    else
      job_spec.each do |field, expected_str|
        if field == "job_stage"
          current_id = cjob.istage?
          expected_id = JOB_STAGE_NAME2ID[expected_str]?
          return false unless current_id && expected_id && current_id >= expected_id
        elsif field == "job_stage"
          current_id = cjob.idata_readiness?
          expected_id = JOB_DATA_READINESS_NAME2ID[expected_str]?
          return false unless current_id && expected_id && current_id >= expected_id
        elsif field == "milestones"
          return false unless cjob.hash_array.has_key?("milestones") && cjob.hash_array["milestones"].includes?(expected_str)
        else
          return false unless cjob.hash_plain[field]? == expected_str
        end
      end
    end

    # Process get_fields
    waited_job = Hash(String, String).new
    waited_job["job_stage"] = cjob.job_stage
    waited_jobs = wait_spec["waited_jobs"] ||= HashHH.new
    waited_jobs[job_id_str] = waited_job
    if wait_options = wait_spec["wait_options"]?
      if get_fields = wait_options["get_fields"]?

        get_fields.each_key do |field|
          waited_job[field] = cjob.hash_plain[field]? ||
                              cjob.hash_array[field]?.try(&.join(" ")) ||
                              cjob.hash_hh[field]?.try(&.to_json) ||
                              ""
        end

      end

      # Process fail_fast
      if wait_options.has_key?("fail_fast") && cjob.job_stage == "incomplete"
        wait_spec.delete("wait_on")
        return :fail_fast
      end
    end

    wait_on.delete(job_id_str)
    wait_spec.delete("wait_on") if wait_spec["wait_on"].empty?
    true
  end

  def api_wait_jobs(env)
    body = env.request.body.not_nil!.gets_to_end
    json = JSON.parse(body)
    wait_spec = wait_json2hash(json)
    return wait_spec.to_json if initial_check(wait_spec)

    client_id, channel = setup_wait_client(wait_spec)
    job_ids = register_wait_client(client_id, wait_spec)

    wait_for_updates(channel, wait_spec) unless job_ids.empty?
  ensure
    cleanup_wait_client(client_id, job_ids) unless job_ids.nil? || job_ids.empty?
    wait_spec
  end

  private def wait_json2hash(json : JSON::Any) : HashHHH
    result = HashHHH.new
    json_h = json.as_h

    # Parse wait_on
    if wait_on_json = json_h["wait_on"]?
      wait_on = HashHH.new
      wait_on_json.as_h.each do |job_id, value|
        if value.raw.is_a?(Nil) || (value.raw.is_a?(Hash) && value.as_h.empty?)
          wait_on[job_id] = nil
        else
          job_hash = HashH.new
          value.as_h.each { |k, v| job_hash[k] = v.as_s }
          wait_on[job_id] = job_hash
        end
      end
      result["wait_on"] = wait_on
    end

    # Parse wait_options
    if wait_options_json = json_h["wait_options"]?
      wait_options = HashHH.new
      wait_options_json.as_h.each do |k, v|
        if k == "get_fields"
          get_fields = HashH.new
          v.as_h.each { |field, _| get_fields[field] = "" }
          wait_options["get_fields"] = get_fields
        else
          wait_options[k] = nil
        end
      end
      result["wait_options"] = wait_options
    end

    # Parse waited_jobs (output only)
    result["waited_jobs"] = HashHH.new
    result
  end

  private def initial_check(wait_spec : HashHHH)
    wait_on = wait_spec["wait_on"]? || return true
    initial_count = wait_on.size
    wait_on.keys.each do |jobid_str|
      job_id = jobid_str.to_i64
      check_wait_spec(job_id, wait_spec)
    end
    initial_count > wait_on.size
  end

  private def setup_wait_client(wait_spec)
    client_id = @@last_wait_client_id
    @@last_wait_client_id -= 1
    if @@last_wait_client_id <= Int64::MIN
      # wrap around, ensure negative
      @@last_wait_client_id = -1
    end

    channel = Channel(Int64).new
    @wait_client_channel[client_id] = channel
    @wait_client_spec[client_id] = wait_spec.dup

    {client_id, channel}
  end

  private def register_wait_client(client_id, wait_spec : HashHHH)
    job_ids = [] of Int64
    if wait_on = wait_spec["wait_on"]?
      wait_on.keys.each do |jobid_str|
        job_id = jobid_str.to_i64
        @jobs_wait_on[job_id] << client_id
        job_ids << job_id
      end
    end
    job_ids
  end

  private def wait_for_updates(channel, wait_spec)
    timeout_channel = Channel(Nil).new
    spawn { sleep 10.seconds; timeout_channel.send(nil) }

    loop do
      select
      when cjob_id = channel.receive
        wait_spec.delete(cjob_id.to_s)
        break # if wait_spec.empty?
      when timeout_channel.receive
        break
      end
    end
  end

  private def cleanup_wait_client(client_id, job_ids)
    job_ids.each do |job_id|
      next unless list = @jobs_wait_on[job_id]?
      list.delete(client_id)
      @jobs_wait_on.delete(job_id) if list.empty?
    end
    @wait_client_channel.delete(client_id)
    @wait_client_spec.delete(client_id)
  end

  # Graceful shutdown cleanup
  def shutdown
      @client_sessions.each_value &.socket.close
      @client_sessions.clear

      @provider_sessions.each_value &.socket.close
      @provider_sessions.clear
  end

  def api_terminate_job(job_id : Int64)
    # Fetch the job and validate its existence
    job = get_job(job_id)
    return HTTP::Status::NOT_FOUND, "Job not found" unless job

    # Validate the job's stage
    unless job.running?
      return HTTP::Status::FORBIDDEN, "Job not running"
    end

    # Attempt to terminate the job and handle errors
    terminate_job(job)
  end

  private def terminate_job(job) : Tuple(HTTP::Status, String)
    host = job.host_machine

    if job.tbox_type == "hw"
      return ipmi_reboot(host)
    else
      provider_ws = @provider_sessions[host]?
      unless provider_ws
        return HTTP::Status::NOT_FOUND, "Provider WebSocket session not found"
      end

      # Send termination command via WebSocket
      begin
        provider_ws.send({type: "terminate-job", job_id: job.job_id}.to_json)
      rescue ex : Exception
        return HTTP::Status::INTERNAL_SERVER_ERROR, "WebSocket send error: #{ex.message}"
      end
    end

    # Return success response
    return HTTP::Status::OK, ""
  end

  def api_provider_websocket(socket, env)
    host = env.params.url["host"]?
    unless host
      socket.close(HTTP::WebSocket::CloseCode::PolicyViolation, "Missing host parameter")
      @log.warn("Missing host parameter")
      return "Missing host parameter"
    end

    session = WebSocketSession.new(WebSocketSession::SessionType::Provider, socket, env)

    # Close existing connection if present
    @provider_sessions[host]?.try(&.socket.close)
    @provider_sessions[host] = session

    socket.on_message do |raw_message|
      begin
        msg = JSON.parse(raw_message).as_h
        case msg["type"]?.try(&.as_s)
        when "host-job-request"
          begin
            # @log.debug("host-job-request: raw_message is #{raw_message}")
            hostreq = HostRequest.from_json(raw_message)
            @hosts_cache.pass_info_to_host(hostreq, msg)
            tbox_request_job(hostreq)
          rescue ex : JSON::ParseException
            @log.error { "Invalid host request format: #{ex.message} raw_message is #{raw_message}" }
          end

        when "job-update"
          params = msg.transform_values(&.to_s)
          update_job_from_hash(params)

        when "console-output", "console-exit", "console-error"
          handle_console_output(msg, raw_message)

        when "job-log"
          handle_job_logs(msg, raw_message)

        else
          @log.warn { "Unknown provider message type: #{msg["type"]?}" }
        end
      rescue ex
        @log.error(exception: ex) { "Error processing provider message #{raw_message}" }
      end
    end

    socket.on_close do
      @provider_sessions.delete(host)
      @log.info { "Provider #{host} disconnected" }
    end
  rescue ex
      @log.error(exception: ex) { "api_provider_websocket error processing client message" }
  end

  def api_client_websocket(socket, env)
    session = WebSocketSession.new(WebSocketSession::SessionType::Client, socket, env)

    @client_sessions[session.sid] = session

    # Send welcome message on connection
    welcome_msg = {
      type:    "welcome",
      sid:     session.sid,
      message: "Welcome to Compass CI scheduler #{Scheduler::VERSION}",
      status:  "connected"
    }.to_json
    session.send(welcome_msg)
    @log.info { "Client #{session.sid} connected" }

    socket.on_message do |raw_message|
      handle_client_message(raw_message, session)
    end

    socket.on_close do
      @client_sessions.delete(session.sid)
      cleanup_session(session.sid)
      @log.info { "Client #{session.sid} disconnected" }
    end
  end

  private def handle_console_output(msg, raw_message)
    job_id = parse_job_id(msg)
    return unless job_id

    if client_sid = @console_jobid2client_sid[job_id]?
      if client_session = @client_sessions[client_sid]?
        client_session.send(raw_message)
      else
        @console_jobid2client_sid.delete(job_id)
        @log.debug { "Cleaned orphaned console session for job #{job_id}" }
      end
    end
  end

  def send_job_event(jobid, event : String)
    return unless @watchjob_jobid2client_sids.has_key?(jobid)

    sids = @watchjob_jobid2client_sids[jobid]
    invalid_sids = [] of Int64

    sids.each do |sid|
      if client_ws = @client_sessions[sid]?
        unless client_ws.send(event)
            invalid_sids << sid
        end
      else
        invalid_sids << sid
      end
    end

    invalid_sids.each { |sid| sids.delete(sid) }
    @watchjob_jobid2client_sids.delete(jobid) if sids.empty?
  end

  private def handle_job_logs(msg, raw_message)
    job_id = parse_job_id(msg)
    return unless job_id

    sids = @watchlog_jobid2client_sids[job_id]?
    return unless sids

    invalid_sids = [] of Int64

    sids.each do |sid|
      if client_ws = @client_sessions[sid]?
        unless client_ws.send(raw_message)
          invalid_sids << sid
        end
      else
        invalid_sids << sid
      end
    end

    invalid_sids.each { |sid| sids.delete(sid) }
    @watchlog_jobid2client_sids.delete(job_id) if sids.empty?
  end

  private def handle_client_message(raw_message, session)
    begin
      msg = JSON.parse(raw_message)

      unless msg.as_h?
        session.send({type: "error", message: "Invalid message format"}.to_json)
        return
      end

      message_type = msg["type"]?.try(&.as_s)
      unless message_type
        session.send({type: "error", message: "Missing message type"}.to_json)
        return
      end

      job_id = parse_job_id(msg)
      unless job_id
        session.send({type: "error", message: "Invalid or missing job_id"}.to_json)
        return
      end

      job = get_job(job_id)
      unless job
        session.send({type: "error", message: "Job #{job_id} not found"}.to_json)
        return
      end

      # job.host_machine is normally nil before dispatch
      host = job.host_machine? || ""
      provider_session = @provider_sessions[host]?

      case message_type
      when "watch-job-event"
        manage_subscription(@watchjob_jobid2client_sids, job_id, session)
        @log.info { "Client #{session.sid} watching job #{job_id} events" }

      when "unwatch-job-event"
        manage_unsubscription(@watchjob_jobid2client_sids, job_id, session)
        @log.info { "Client #{session.sid} unwatched job #{job_id} events" }

      when "watch-job-log"  # serial logs
        manage_subscription(@watchlog_jobid2client_sids, job_id, session)
        forward_or_buffer_message(provider_session, job, raw_message, "log subscription")

      when "unwatch-job-log"
        manage_unsubscription(@watchlog_jobid2client_sids, job_id, session)
        forward_or_buffer_message(provider_session, job, raw_message, "log unsubscription")

      when "request-console"
        @console_jobid2client_sid[job_id] = session.sid
        forward_or_buffer_message(provider_session, job, raw_message, "console request")

      when "console-input", "resize-console"
        handle_console_input(provider_session, job, host, raw_message)

      when "close-console"
        @console_jobid2client_sid.delete(job_id)
        forward_or_buffer_message(provider_session, job, raw_message, "console closure")

      else
        session.send({type: "error", message: "Unknown message type: #{message_type}"}.to_json)
      end

    rescue ex : JSON::ParseException
      @log.error { "JSON parse error: #{ex.message}" }
      session.send({type: "error", message: "Invalid JSON format"}.to_json)
    rescue ex
      @log.error(exception: ex) { "Error processing message" }
      session.send({type: "error", message: "Internal server error"}.to_json)
    end
  end

  # Helper methods
  private def parse_job_id(msg)
    if msg["job_id"]?
      msg["job_id"].as_s.to_i64
    else
      nil
    end
  end

  private def manage_subscription(subscription_hash, job_id, session)
    subscription_hash[job_id] ||= Array(Int64).new
    subscription_hash[job_id] << session.sid
  end

  private def manage_unsubscription(subscription_hash, job_id, session)
    return unless subscription_hash[job_id]?
    subscription_hash[job_id].delete(session.sid)
    subscription_hash.delete(job_id) if subscription_hash[job_id].empty?
  end

  private def forward_or_buffer_message(provider, job, message, context)
    if provider
      provider.send(message)
    else
      job.hash_array["pending_messages"] ||= [] of String
      job.pending_messages << message
      @log.debug { "Buffered #{context} for job #{job.id}" }
    end
  end

  private def handle_console_input(provider, job, host, message)
    if provider
      provider.send(message)
    elsif channel = @hw_serial_login_channels[host]?
      channel.send(message)
    else
      # job.pending_messages ||= [] of String
      # job.pending_messages << message
      # @log.warn { "Buffered console input for job #{job.id}" }
    end
  end

  private def cleanup_session(sid : Int64)
    # Remove from console mappings
    @console_jobid2client_sid.reject! { |_, client_sid| client_sid == sid }

    # Remove from log watchers
    @watchlog_jobid2client_sids.each do |job_id, sids|
      @watchlog_jobid2client_sids[job_id] = sids.reject { |s| s == sid }
    end

    @watchjob_jobid2client_sids.each do |job_id, sids|
      @watchjob_jobid2client_sids[job_id] = sids.reject { |s| s == sid }
    end
  end

end
