# encoding: UTF-8
require "sinatra"
require "json"
require "open3"

set :bind, "0.0.0.0"
set :port, 8100

$GIT = "/git"

post '/git_command' do
  request.body.rewind
  begin
    data = JSON.parse request.body.read
  rescue
    return JSON.dump({"status": 0, "errmsg": "parse json error"})
  end
  if !data.has_key?("project") or !data.has_key?("developer_repo") or !data.has_key?("git_command")
    return JSON.dump({"status": 0, "errmsg": "params has error"})
  end
  repo_path = File.join($GIT, data["project"], data["developer_repo"])
  if !File.exist?(repo_path)
    return JSON.dump({"status": 0, "errmsg": "repository not exists"})
  end
  cmd = "cd " + repo_path + " && " + data["git_command"]
  stdin, stdout, stderr = Open3.popen3(cmd)
  out= stdout.read.force_encoding("ISO-8859-1").encode("UTF-8")
  err=stderr.read
  #return JSON.dump({"status": 1, "stdout": out, "stderr": err}) 
  {"status": 1, "stdout": out, "stderr": err}.to_json 


end
