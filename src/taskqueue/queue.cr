# SPDX-License-Identifier: MulanPSL-2.0+ or GPL-2.0
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "uuid"

require "./redis_client"

class TaskQueue
  def queue_respond_add(env)
    body = env.request.body
    if body.nil?
      return queue_respond_header_set(env, 400, "Missing http body")
    end

    queue_name, ext_set = queue_check_params(env, ["queue"])
    return ext_set if ext_set

    type, prefix = get_matched_queue_name(queue_name[0])
    param_queue = "#{prefix}/#{type}"

    body_content = body.gets_to_end
    env.request.body = body_content # restore back for debug message

    task_content = JSON.parse(body_content)
    id = task_content["id"]?
    if id
      case task_in_queue_status(id.to_s, param_queue)
      when TaskInQueueStatus::TooBigID
        return queue_respond_header_set(env, 409,
          "Add with error id <#{id}>")
      when TaskInQueueStatus::SameQueue
        return queue_respond_header_set(env, 409,
          "Queue <#{queue_name[0]}> already has id <#{id}>")
      when TaskInQueueStatus::SameService
        service_name = service_name_of_queue(param_queue)
        return queue_respond_header_set(env, 409,
          "Service <#{service_name}> still has id <#{id}> in process")
      when TaskInQueueStatus::InTaskQueue
        return queue_respond_header_set(env, 409,
          "TaskQueue still has id <#{id}> in process")
      when TaskInQueueStatus::NotExists
      end
    else
      return queue_respond_header_set(env, 409, "Need the lab in the task content") unless task_content["lab"]?
    end

    task_id = add2redis("#{param_queue}", task_content.as_h)
    env.response.status_code = 200
    {id: task_id}.to_json
  end

  def queue_respond_header_set(env, code, message)
    env.response.status_code = code
    env.response.headers.add("CCI-Error-Description", message)
  end

  def queue_check_params(env, parameter_list)
    params = Array(String).new
    ext_set = nil

    parameter_list.each do |parameter_name|
      parameter_value = env.params.query[parameter_name]?

      if parameter_value.nil?
        ext_set = queue_respond_header_set(env, 400, "Missing parameter <#{parameter_name}>")
        return params, ext_set
      end
      params << parameter_value
    end

    return params, ext_set
  end

  def queue_respond_consume(env)
    queue_name, ext_set = queue_check_params(env, ["queue"])
    return ext_set if ext_set

    # type can be "idle" | "ready", can not be "uuid"
    type, prefix = get_matched_queue_name(queue_name[0])
    queue_name_from = "#{prefix}/#{type}"
    case type
    when "ready"
      move_uuid_task2ready(prefix)
    when "idle"
      # doing noting
    else # uuid
      puts "Warring: Should not direct comsume job with uuid."
    end

    queue_name_from = "#{prefix}/#{type}"
    queue_name_to = prefix + "/in_process"

    begin
      timeout = "#{env.params.query["timeout"]?}".to_i
      timeout = HTTP_MAX_TIMEOUT if timeout > HTTP_MAX_TIMEOUT
    rescue
      timeout = HTTP_DEFAULT_TIMEOUT
    end

    task = operate_with_timeout(timeout) {
      move_first_task_in_redis(queue_name_from, queue_name_to)
    }

    if task.nil?
      env.response.status_code = 201
    else
      env.response.status_code = 200
    end
    return task
  end

  def queue_respond_hand_over(env)
    params, ext_set = queue_check_params(env, ["from", "to", "id"])
    return ext_set if ext_set

    from = params[0] + "/in_process"
    to = params[1] + "/ready"
    id = params[2]

    if move_task_in_redis(from, to, id)
      env.response.status_code = 201
    else
      queue_respond_header_set(env, 409, "Can not find id <#{id}> in queue <#{params[0]}>")
    end
  end

  def service_name_of_queue(queue_name : String)
    find_slash = queue_name.index('/')
    return find_slash ? queue_name[0, find_slash] : queue_name
  end

  def queue_respond_delete(env)
    params, ext_set = queue_check_params(env, ["queue", "id"])
    return ext_set if ext_set

    # input queue parameter may like "scheduler/$tbox_group/..."
    #   we just need make sure the "id" blongs to queue "scheduler"
    #   the (queue "scheduler") is a queue for scheduler-service
    queue = service_name_of_queue(params[0])
    id = params[1]

    if delete_task_in_redis(queue, id)
      env.response.status_code = 201
    else
      queue_respond_header_set(env, 409, "Can not find id <#{id}> in queue <#{params[0]}>")
    end
  end

  def queue_respond_keys(env)
    queue_name_pattern, ext_set = queue_check_params(env, ["queue"])
    return ext_set if ext_set

    response = get_keys(queue_name_pattern[0])
    env.response.status_code = 201 if response.empty?

    return response
  end

  # loop try: when there has no task, return until get one or timeout
  # default timeout is 0.015ms, we delay for 10ms at each time
  private def operate_with_timeout(timeout)
    result = nil
    time_span = Time::Span.new(nanoseconds: (REDIS_POOL_TIMEOUT + 1) * 1000)
    time_start = Time.local.to_unix_f
    timeout_seconds_f = timeout / 1000

    loop do
      result = yield
      break if result

      break if (Time.local.to_unix_f - time_start) > timeout_seconds_f
      sleep(time_span)
    end

    return result
  end

  private def get_matched_queue_name(queue_name)
    test_queue_name = "#{queue_name}"
    match = test_queue_name.match(/(.*)\/(.*)$/)
    if !match.nil?
      return "idle", match[1] if match[2] == "idle"

      begin
        uuid = UUID.new(match[2])
        return uuid.to_s, match[1]
      rescue
      end
    end

    return "ready", test_queue_name
  end

  private def move_uuid_task2ready(queue_name)
    # get uuid lists
    # uuid_keys ["queues/sched/vm-2p8g/ee44b164-90e3-49a7-9798-5e7cc9bc7451", ]
    uuid_keys = get_uuid_keys("#{queue_name}")
    return unless uuid_keys # nil
    return unless uuid_keys.size > 0

    # move task to ready, and with rate control to each uuid
    uuid_keys.each do |key|
      uuid, prefix = get_matched_queue_name(key)
      if @@rate_limiter.rate_limited?(:l48pD, uuid) == false
        # prefix is start with "queues", need delete it
        s_name = prefix.sub("#{QUEUE_NAME_BASE}/", "")
        move_first_task_in_redis_with_score("#{s_name}/#{uuid}",
          "#{s_name}/ready")
      end
    end
  end
end
