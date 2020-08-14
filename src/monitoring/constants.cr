MQ_HOST = (ENV.has_key?("MQ_HOST") ? ENV["MQ_HOST"] : "172.17.0.1")
MQ_PORT = (ENV.has_key?("MQ_PORT") ? ENV["MQ_PORT"] : 5672).to_i32

MONITOR_PORT = (ENV.has_key?("MONITOR_PORT") ? ENV["MONITOR_PORT"] : 11310).to_i32
