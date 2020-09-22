# SPDX-License-Identifier: MulanPSL-2.0+ or GPL-2.0
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "kemal"

require "./constants"
require "./queue"

class TaskQueue
  VERSION = "0.0.2"

  def debug_message(env, response, time_in)
    puts("\n")

    from_message = "#{time_in} --> #{env.request.remote_address}"
    if env.request.body != nil
      from_message += " #{env.request.body}"
    end
    puts(from_message)

    puts("#{Time.utc} <-- #{response}")
  end

  def run
    # -------------------
    # request: curl http://localhost:3060
    #
    # response: TaskQueue@v0.0.1 is alive.
    get "/" do |env|
      response = "TaskQueue@v#{VERSION} is alive."
      debug_message(env, response, Time.utc)

      "#{response.to_json}\n"
    end

    # -------------------
    # request: curl -X POST http://localhost:3060/add?queue=scheduler/$tbox_group
    #               -H "Content-Type: application/json"
    #               --data '{"suite":"test01", "tbox_group":"host"}'
    #          |    --data '{"suite":"test01", "id":$id, "tbox_group":"host"}'
    #
    # response: 200 {id: 1}.to_json
    #           409 "Queue <scheduler/host> already has id <$id>"
    #           409 "Add with error id <65536>"
    #           400 "Missing parameter <queue>"
    #           400 "Missing http body"
    post "/add" do |env|
      response = queue_respond_add(env)
      debug_message(env, response, Time.utc)
      response if env.response.status_code == 200
    end

    # -------------------
    # request: curl -X PUT http://localhost:3060/consume?queue=scheduler/$tbox_group
    #   option parameter timeout=XXXX (default as 3000ms, max 57000ms)
    #
    # response: 200 {"suite":"test01", "tbox_group":"host", "id":1}.to_json
    #           201 ## when there has no task in queue (scheduler/$tbox_group)
    #           400 "Missing parameter <queue>"
    put "/consume" do |env|
      response = queue_respond_consume(env)
      debug_message(env, response, Time.utc)
      response if env.response.status_code == 200
    end

    # -------------------
    # request: curl -X PUT http://localhost:3060/hand_over?
    #          from=scheduler/$tbox_group&to=extract_stats&id=$id
    #
    # response: 201 ## when succeed hand over
    #           400 "Missing parameter <from|to|id>"
    #           409 "Can not find id <$id> in queue <scheduler/$tbox_group>"
    put "/hand_over" do |env|
      response = queue_respond_hand_over(env)
      debug_message(env, response, Time.utc)
      nil
    end

    # -------------------
    # request: curl -X PUT http://localhost:3060/delete?
    #          from=scheduler/$tbox_group&id=$id
    #
    # response: 201 ## when succeed delete
    #           400 "Missing parameter <queue|id>"
    #           409 "Can not find id <$id> in queue <scheduler/$tbox_group>"
    put "/delete" do |env|
      response = queue_respond_delete(env)
      debug_message(env, response, Time.utc)
      nil
    end

    @port = (ENV.has_key?("TASKQUEUE_PORT") ? ENV["TASKQUEUE_PORT"].to_i32 : TASKQUEUE_PORT)
    Kemal.run(@port)
  end
end
