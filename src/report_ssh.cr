# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def report_ssh_port(env)
    testbox = env.params.query["tbox_name"]
    ssh_port = env.params.query["ssh_port"].to_s
    job_id = env.params.query["job_id"].to_s

    @log.info({"job_id" => "#{job_id}", "state" => "set ssh port", "ssh_port" => "#{ssh_port}", "tbox_name" => "#{testbox}"})
  rescue e
    @log.warn(e)
  end

  def report_ssh_info(env)
    body =  env.request.body.not_nil!.gets_to_end
    ssh_info = JSON.parse(body).as_h
    ssh_port = ssh_info["ssh_port"]?.to_s

    if ssh_port.empty?
      # The client command "submit -m -c" determines whether to execute SSH
      # base on whether the key "ssh_port" exists.
      # Therefore, if the key is empty, delete the key.
      ssh_info.delete("ssh_port")
    end

    ssh_info["state"] = JSON::Any.new("set ssh port")
    @log.info { ssh_info.to_json }
  end
end
