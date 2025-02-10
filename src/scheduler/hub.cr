
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
  def send(message : String) : Nil
    return if closed?

    begin
      @socket.send(message)
    rescue ex : IO::Error
      Log.error(exception: ex) { "Failed to send message to session #{sid}" }
    end
  end
end

class Sched

  property client_sessions = {} of Int64 => WebSocketSession
  property provider_sessions = {} of String => WebSocketSession

  property console_jobid2client_sid = {} of Int64 => Int64
  property watchlog_jobid2client_sids = {} of Int64 => Array(Int64)

  # << hosts write job request to it
  # >> dispatch worker reads them, find job, then
  # - tbox_type = hw: write to hw_machine_channels[host]
  # - tbox_type = vm|dc: write to provider_sessions[host].socket
  @host_request_job_channel = Channel(HostRequest).new
  @hw_machine_channels = {} of String => Channel(JobHash)
  @host_requests = [] of HostRequest  # Using sorted array instead of PriorityQueue

  @wait_client_channel = Hash(Int64, Channel(Int64)).new # /scheduler/wait-jobs clientid => Channel(jobid)
  @wait_client_spec = Hash(Int64, HashHH).new
  @@last_wait_client_id : Int64 = -1_i64

  property jobs_cache = Hash(Int64, JobHash).new

  # on updated job fields, should check this mapping to wake up possible jobs/clients
  # @jobs_wait_by[job.wait_on.keys.each] << job.id64
  # @jobs_wait_by[jobid] << negative clientid
  property jobs_wait_by = Hash(Int64, Array(Int64)).new  # Array(Int64) is waiting for first Int64

  def get_job(job_id : Int64) : JobHash?
    job = @jobs_cache[job_id]? ||
          @jobs_cache_in_submit[job_id]?
    return job if job

    job = @es.get_job(job_id.to_s)
    add_job_to_cache(job) if job
    job
  end

  def on_job_updated(job_id : Int64)
    return unless @jobs_wait_by.has_key? job_id
    return unless job = get_job(job_id)

    @jobs_wait_by[job_id].each do |id|
      if id >= 0
        # another job is waiting for me
        handle_job_dependency(id, job)
      else
        # a http post "/scheduler/wait-jobs" client is waiting for me
        handle_client_dependency(id, job_id)
      end
    end
  end

  private def handle_job_dependency(dependent_id : Int64, job : JobHash)
    dependent_job = get_job(dependent_id)
    return unless dependent_job && (wait_spec = dependent_job.hash_hhh["wait_on"]?)

    if check_wait_spec(job.id64, wait_spec)
      dependent_job.hash_hhh.delete("wait_on")
      add_job_to_cache(dependent_job)
      @jobs_cache.delete(dependent_id)
    end
  end

  private def handle_client_dependency(client_id : Int64, job_id : Int64)
    client_spec = @wait_client_spec[client_id]?
    return unless client_spec

    job_spec = client_spec[job_id.to_s]?
    return unless job_spec

    if check_wait_spec(job_id, job_spec)
      @wait_client_channel[client_id]?.try &.send(job_id)
    end
  end

  # return true if all match; false if any not match
  def check_wait_spec(job_id : Int64, wait_spec : Hash | Nil)
    return unless wait_spec

    job = get_job(job_id)
    return unless job

    wait_spec.each do |field, expected|
      expected_str = expected

      if field == "job_stage"
        job_value = job.job_stage
        current_id = JOB_STAGE_NAME2ID[job_value]?
        expected_id = JOB_STAGE_NAME2ID[expected_str]?
        return false unless current_id && expected_id
        return false unless current_id >= expected_id
      end

      if field == "milestones"
        # XXX: currently there's only need to wait on single milestone value
        return false unless job.hash_array.has_key? "milestones"
        return false unless job.hash_array[field].includes? expected_str
      end

      return false unless job.hash_plain.has_key? field
      job_value = job.hash_plain[field]
      if job_value != expected_str
        return false
      end
    end

    true
  end

  def api_wait_jobs(env)
    body = env.request.body.not_nil!.gets_to_end
    wait_spec = wait_json2hash(JSON.parse(body).as_h)
    return wait_spec.to_json if initial_check(wait_spec)

    client_id, channel = setup_wait_client(wait_spec)
    job_ids = register_wait_client(client_id, wait_spec)

    wait_for_updates(channel, wait_spec)
  ensure
    cleanup_wait_client(client_id, job_ids) if job_ids
    wait_spec.to_json
  end

  # example input:
  # {
  #   jobid1: { field1: value1 },
  #   jobid2: { field1: value2, field2: value3 },
  #   jobid3: { },
  # }
  private def wait_json2hash(json : Hash(String, JSON::Any)) : HashHH
    result = HashHH.new

    json.each do |job_id, value|
      job_hash = HashH.new
      if value.is_a?(Nil) || (value.is_a?(Hash) && value.empty?)
        # Create a default hash for empty jobs
        job_hash["job_stage"] = "complete"
      else
        # Convert the JSON::Hash to HashH with string values
        value.as_h.each do |field, jval|
          job_hash[field] = jval.as_s
        end
      end

      result[job_id] = job_hash
    end

    result
  end

  private def initial_check(wait_spec)
    nr = wait_spec.size
    wait_spec.reject! do |jobid_str, spec|
      job_id = jobid_str.to_i64
      check_wait_spec(job_id, spec)
    end
    nr > wait_spec.size
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

  private def register_wait_client(client_id, wait_spec)
    job_ids = wait_spec.keys.map(&.to_i64)
    job_ids.each do |job_id|
      @jobs_wait_by[job_id] ||= [] of Int64
      @jobs_wait_by[job_id] << client_id
    end
    job_ids
  end

  private def wait_for_updates(channel, wait_spec)
    timeout_channel = Channel(Nil).new
    spawn { sleep 10.seconds; timeout_channel.send(nil) }

    loop do
      select
      when job_id = channel.receive
        wait_spec.delete(job_id.to_s)
        break # if wait_spec.empty?
      when timeout_channel.receive
        break
      end
    end
  end

  private def cleanup_wait_client(client_id, job_ids)
    job_ids.each do |job_id|
      next unless list = @jobs_wait_by[job_id]?
      list.delete(client_id)
      @jobs_wait_by.delete(job_id) if list.empty?
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
    job = get_job(job_id)
    return unless job
    return unless ["booting", "running"].includes? job.job_stage
    terminate_job(job)
  end

  def terminate_job(job)
    host = job.host_machine
    if job.tbox_type == "hw"
      ipmi_reboot(host)
    else
      provider_ws = @provider_sessions[host]
      provider_ws.send({ type: "terminate-job", job_id: job.job_id }.to_json)
    end
  end

  def api_provider_websocket(socket, env)
    host = env.params.url["host"]?
    unless host
      socket.close(HTTP::WebSocket::CloseCode::PolicyViolation, "Missing host parameter")
      return
    end

    session = WebSocketSession.new(WebSocketSession::SessionType::Provider, socket, env)

    # Close existing connection if present
    @provider_sessions[host]?.try(&.socket.close)
    @provider_sessions[host] = session

    socket.on_message do |raw_message|
      begin
        msg = JSON.parse(raw_message)

        case msg["type"]?.try(&.as_s)
        when "host-job-request"
          begin
            hostreq = HostRequest.from_json(raw_message)
            record_hostreq(hostreq)
          rescue ex : JSON::ParseException
            Log.error { "Invalid host request format: #{ex.message}" }
          end

        when "console-output"
          handle_console_output(msg, raw_message)

        when "job-log"
          handle_job_logs(msg, raw_message)

        else
          Log.warn { "Unknown provider message type: #{msg["type"]?}" }
        end
      rescue ex
        Log.error(exception: ex) { "Error processing provider message" }
      end
    end

    socket.on_close do
      @provider_sessions.delete(host)
      Log.info { "Provider #{host} disconnected" }
    end
  end

  def api_client_websocket(socket, env)
    session = WebSocketSession.new(WebSocketSession::SessionType::Client, socket, env)

    @client_sessions[session.sid] = session

    socket.on_message do |raw_message|
      handle_client_message(raw_message, session)
    end

    socket.on_close do
      @client_sessions.delete(session.sid)
      cleanup_session(session.sid)
      Log.info { "Client #{session.sid} disconnected" }
    end
  end

  private def handle_console_output(msg, raw_message)
    job_id = msg["job_id"]?.try(&.as_s.to_i64?)
    return unless job_id

    if client_sid = @console_jobid2client_sid[job_id]?
      if client_session = @client_sessions[client_sid]?
        client_session.send(raw_message)
      else
        # Cleanup orphaned console session
        @console_jobid2client_sid.delete(job_id)
      end
    end
  end

  private def handle_job_logs(msg, raw_message)
    job_id = msg["job_id"]?.try(&.as_s.to_i64?)
    return unless job_id

    sids = @watchlog_jobid2client_sids[job_id]
    sids.each do |sid|
      client_ws = @client_sessions[sid]
      client_ws.send(raw_message)
    end
  end

  private def handle_client_message(raw_message, session)
    begin
      msg = JSON.parse(raw_message)
      job_id = msg["job_id"]?.try(&.as_s.to_i64?)

      unless job_id
        session.send({type: "error", message: "Missing job_id"}.to_json)
        return
      end

      job = get_job(job_id)
      unless job
        session.send({type: "error", message: "Job #{job_id} not found"}.to_json)
        return
      end

      host = job.host_machine
      provider_session = @provider_sessions[host]?

      unless provider_session
        session.send({type: "error", message: "Provider #{host} unavailable"}.to_json)
        return
      end

      case msg["type"]?.try(&.as_s)
      when "watch-job-log", "request-console", "console-input"
        provider_session.send(raw_message)

        # Track console sessions
        if msg["type"].as_s == "request-console"
          @console_jobid2client_sid[job_id] = session.sid
        end

      when "close-console"
        provider_session.send(raw_message)
        @console_jobid2client_sid.delete(job_id)

      else
        session.send({type: "error", message: "Unknown message type"}.to_json)
      end
    rescue ex
      Log.error(exception: ex) { "Error processing client message" }
      session.send({type: "error", message: "Internal server error"}.to_json)
    end
  end

  private def cleanup_session(sid : Int64)
    # Remove from console mappings
    @console_jobid2client_sid.reject! { |_, client_sid| client_sid == sid }

    # Remove from log watchers
    @watchlog_jobid2client_sids.each do |job_id, sids|
      @watchlog_jobid2client_sids[job_id] = sids.reject { |s| s == sid }
    end
  end

end
