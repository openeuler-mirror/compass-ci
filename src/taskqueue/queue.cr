require "./redis_client"

class TaskQueue

  def queue_respond_add(env)
    body = env.request.body
    if body.nil?
      return queue_respond_header_set(env, 400, "Missing http body")
    end

    queue_name = env.params.query["queue"]?
    if queue_name.nil?
      return queue_respond_header_set(env, 400, "Missing parameter <queue>")
    end

    queue_name = queue_name + "/ready"

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
end
