# SPDX-License-Identifier: MulanPSL-2.0+ or GPL-2.0
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "kemal"
require "rate_limiter"

require "./constants"
require "./queue"

class TaskQueue
  VERSION = "0.0.2"

  # l2pH: limit 2 / hours
  # l100pms: limit 100 / ms
  @@rate_limiter = RateLimiter(String).new
  @@rate_limiter.bucket(:l48pD, 48_u32, 1.days)
  @@rate_limiter.bucket(:l2pH, 1_u32, 30.minutes)
  @@rate_limiter.bucket(:l1pms, 1_u32, 0.001.seconds)
  @@rate_limiter.bucket(:l100pms, 1_u32, 0.00001.seconds)

  # logs example:
  #  from: {172.17.0.1:6952} body {"domain":"compass-ci"} <-- ack: {"id":"z9.134780"}
  #  | from: {172.17.0.1:6952} <-- ack: {}
  #  2020-10-19 03:25:01 UTC 201 PUT /consume?queue=sched%2Fdc-2g%2Fidle 356.51µs
  #
  # "from" is puts by this debug_message
  # "2020-10..." auto puts by kemal frame, time in {2020-10-19 03:25:01 UTC} and span {356.51us}
  def debug_message(env, response, time_in)
    logs = "from: {#{env.request.remote_address}}"

    logs += " body: #{env.request.body}" if env.request.body

    logs += " <-- ack: "
    logs += response ? "#{response}" : "{}"

    puts(logs)
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

    # -------------------
    # request: curl http://localhost:3060/keys?
    #          queue=sched*
    #   wild match: *, ?, [-]
    #
    # response: 200 ["scheda", "schedb", ...]
    #           201 ## when no find
    #           400 "Missing parameter <queue>"
    #           413 "Query results too large keys"
    get "/keys" do |env|
      response = queue_respond_keys(env)
      # debug_message(env, response, Time.utc) # maybe too large
      response.to_json unless env.response.status_code == 201
    end

    @port = (ENV.has_key?("TASKQUEUE_PORT") ? ENV["TASKQUEUE_PORT"].to_i32 : TASKQUEUE_PORT)
    Kemal.run(@port)
  end
end
