post "/ws/console" do |env|
  ws = env.websocket?
  job_id = nil

  ws.on_open do
    # Authenticate and authorize the user here
  end

  ws.on_message do |msg|
    data = JSON.parse(msg)
    case data["type"]
    when "request-console"
      job_id = data["job_id"]
      forward_to_testbox(job_id, { type: "request-console" }.to_json)
    when "console-input"
      forward_to_testbox(job_id, msg)
    end
  end

  ws.on_close do
    forward_to_testbox(job_id, { type: "close-console" }.to_json)
  end
end

def forward_to_testbox(job_id, message)
  testbox_socket = @sockets[job_id]
  testbox_socket.emit("console", message) if testbox_socket
end
