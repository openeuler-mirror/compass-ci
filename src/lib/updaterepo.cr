# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "json"
require "kemal"
require "./json_logger"
require "./mq"

# -------------------------------------------------------------------------------------------------------------------------------------
# end_user:
# - restful API [post "/upload"] to post data {"upload_rpms": ["/srv/rpm/upload/**/Packages/*.rpm", "/srv/rpm/upload/**/source/*.rpm"]}
#
# -------------------------------------------------------------------------------------------------------------------------------------
# Repo:
# - get json formated request data
# - use @mq.queue("update_repo") publish data
# - json formated data stored in the @mq.queue("update_repo")
#
class Repo
  def initialize(env : HTTP::Server::Context)
    @mq = MQClient.instance
    @env = env
    @log = JSONLogger.new
  end

  def upload_repo
    begin
      body = @env.request.body.not_nil!.gets_to_end
      data = JSON.parse(body.to_s).as_h?
    rescue e
      @log.warn(e)
    end
    @log.info(data.to_json)

    begin
      check_params_complete(data)
      mq_publish(data)
    rescue e
      @log.warn(e)
      response = { "errcode" => "101", "errmsg" => "upload rpm failed" }
      @log.warn(response.to_json)
    end
  end

  def mq_publish(data)
    mq_msg = data
    spawn mq_publish_check("update_repo", mq_msg.to_json)
  end

  def mq_publish_check(queue, msg)
    3.times do
      @mq.publish_confirm(queue, msg)
      break
    rescue e
      res = @mq.reconnect
      sleep 5
    end
  end

  def check_params_complete(params)
    params = params.not_nil!
    tmp_hash = {"errcode" => "101", "errmsg" => "no upload_rpms params"}.to_json
    raise tmp_hash unless params["upload_rpms"]?
  end
end
