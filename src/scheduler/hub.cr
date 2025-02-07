
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

# Thread-safe scheduler state management
class Sched

  property client_sessions = {} of Int64 => WebSocketSession
  property provider_sessions = {} of String => WebSocketSession

  property console_jobid2client_sid = {} of Int64 => Int64
  property watchlog_jobid2client_sids = {} of Int64 => Array(Int64)

  property jobs_cache = Hash(Int64, JobHash).new

  def get_job(job_id : Int64) : JobHash?
    job = @es.get_job(job_id.to_s)
    @jobs_cache[job_id] if job
    job
  end

  # Graceful shutdown cleanup
  def shutdown
      @client_sessions.each_value &.socket.close
      @client_sessions.clear

      @provider_sessions.each_value &.socket.close
      @provider_sessions.clear
  end

  def stop_job(job_id : Int64)
    job = get_job(job_id)
    return unless job
    host = job.host_machine
    provider_ws = @provider_sessions[host]
    provider_ws.send({ type: "stop-job", job_id: job_id }.to_json)
  end

  def handle_provider_websocket(socket, env)
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

  def handle_client_websocket(socket, env)
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
