# SPDX-License-Identifier: MulanPSL-2.0+

require "json"
require "http/client"

class RemoteGitClient
  def initialize
    @host = ENV.has_key?("REMOTE_GIT_HOST") ? ENV["REMOTE_GIT_HOST"] : "172.17.0.1"
    @port = ENV.has_key?("REMOTE_GIT_PORT") ? ENV["REMOTE_GIT_PORT"].to_i32 : 8100
  end

  def git_command(data : JSON::Any)
    response = HTTP::Client.post("http://#{@host}:#{@port}/git_command", body: data.to_json)
    return response
  end
end
