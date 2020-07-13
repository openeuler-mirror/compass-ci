require "./redis_client"

class TaskQueue

  def queue_respond_add(env)
    body = env.request.body
    if body.nil?
      return queue_respond_header_set(env, 400, "Missing http body")
    end

    queue_name, ext_set = queue_check_params(env, ["queue"])
    return ext_set if ext_set

    queue_name = queue_name[0] + "/ready"

    task_content = JSON.parse(body.gets_to_end)
    id = task_content["id"]?
    if id
      if task_in_queue(id.to_s, queue_name)
        return queue_respond_header_set(env, 409, \
                   "Queue <#{queue_name}> already has id <#{id}>")
      end
    end

    task_id = add2redis("#{queue_name}", task_content.as_h)
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

    queue_name_from = queue_name[0] + "/ready"
    queue_name_to   = queue_name[0] + "/in_process"

    if id = find_first_task_in_redis(queue_name_from)
      env.response.status_code = 200
      task = move_task_in_redis(queue_name_from, queue_name_to, id)
    else
      env.response.status_code = 201
      task = nil
    end

    return task
  end

  def queue_respond_hand_over(env)
    params, ext_set = queue_check_params(env, ["from", "to", "id"])
    return ext_set if ext_set

    from = params[0] + "/in_process"
    to   = params[1] + "/ready"
    id   = params[2]

    if move_task_in_redis(from, to, id)
      env.response.status_code = 201
    else
      queue_respond_header_set(env, 409, "Can not find id <#{id}> in queue <#{params[0]}>")
    end

    return nil
  end

  def get_service_name_of_queue(queue_name : String)
    find_slash = queue_name.index('/')
    return find_slash ? queue_name[0, find_slash] : queue_name
  end

  def queue_respond_delete(env)
    params, ext_set = queue_check_params(env, ["queue", "id"])
    return ext_set if ext_set

    # input queue parameter may like "scheduler/$tbox_group/..."
    #   we just need make sure the "id" blongs to queue "scheduler"
    #   the (queue "scheduler") is a queue for scheduler-service
    queue = get_service_name_of_queue(params[0])
    id    = params[1]

    if delete_task_in_redis(queue, id)
      env.response.status_code = 201
    else
      queue_respond_header_set(env, 409, "Can not find id <#{id}> in queue <#{params[0]}>")
    end

    return nil
  end
end
