# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "json"
require "http/client"

def loop_till_connectable
  loop do
    begin
      return yield
    rescue ex
      puts "#{ex}, retrying in 5s..."
      sleep(5.seconds)
    end
  end
end

class TaskQueueAPI
  def initialize
    @port = ENV.has_key?("TASKQUEUE_PORT") ? ENV["TASKQUEUE_PORT"].to_i32 : 3060
    @host = ENV.has_key?("TASKQUEUE_HOST") ? ENV["TASKQUEUE_HOST"] : "172.17.0.1"
  end

  def add_task(service_queue_path : String, task : JSON::Any)
    params = HTTP::Params.encode({"queue" => service_queue_path})
    client = HTTP::Client.new(@host, port: @port)
    response = loop_till_connectable { client.post("/add?" + params, body: task.to_json) }
    client.close()
    arrange_response(response)
  end

  def query_keys(service_key_with_wild_char : String)
    params = HTTP::Params.encode({"queue" => service_key_with_wild_char})
    client = HTTP::Client.new(@host, port: @port)
    response = loop_till_connectable { client.get("/keys?" + params) }
    client.close()
    arrange_response(response)
  end

  def consume_task(service_queue_path : String)
    params = HTTP::Params.encode({"queue" => service_queue_path})
    response_put_api("consume", params)
  end

  def hand_over_task(service_queue_path_from : String, service_queue_path_to : String, task_id : String)
    params = HTTP::Params.encode({"from" => service_queue_path_from, "to" => service_queue_path_to, "id" => task_id})
    response_put_api("hand_over", params)
  end

  def delete_task(service_queue_path : String, task_id : String)
    params = HTTP::Params.encode({"queue" => service_queue_path, "id" => task_id})
    response_put_api("delete", params)
  end

  private def response_put_api(cmd : String, params : String)
    client = HTTP::Client.new(@host, port: @port)
    response = loop_till_connectable { client.put("/#{cmd}?" + params) }
    client.close()
    arrange_response(response)
  end

  private def arrange_response(response)
    case status_code = response.status_code
    when 200
      [status_code, JSON.parse(response.body)]
    when 201
      [status_code, nil]
    else
      if response.headers["CCI-error-Description"]?
        [status_code, response.headers["CCI-error-Description"]]
      else
        [status_code, response.status_message]
      end
    end
  end
end
