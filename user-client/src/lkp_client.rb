require 'yaml'
require 'json'
require 'base64'
require 'rest-client'

#
class LkpClient
  attr_accessor :server

  def initialize(server)
    @server = server
  end

  def cmd(cmd)
    cmdlist = cmd.split(' ')
    @operate = cmdlist[1]
    @path = cmdlist[2]
  end

  def basic_authorization
    user_name = 'username'
    user_pass = 'password'

    @auth = 'Basic ' + Base64.encode64("#{user_name}:#{user_pass}").chomp
    resource = RestClient::Resource.new("http://#{@server.host}:#{@server.port}/",
                                        { headers: { 'Authorization' => @auth } })
    resource.get
  end

  def trans(file_path)
    all_lines = ''
    File.open(file_path) do |file|
      lines = file.readlines
      lines.each do |line|
        line.gsub!(/^#(.*)\n$/, ":#\\1: \n")
      end
      all_lines = lines.join
    end

    yaml = YAML::parse(all_lines)
    yaml.to_ruby.to_json
  end

  def post_cmd
    resource = RestClient::Resource.new("http://#{@server.host}:#{@server.port}/queues",
                                        { headers: { 'Authorization' => @auth} })
    resource.post(trans(@path))
  end

  def get_cmd
    resource = RestClient::Resource.new("http://#{@server.host}:#{@server.port}/queues",
                                        { headers: { 'Authorization' => @auth,
                                                     :jobid => '@path' } })
    resource.get
  end

  def run
    case @operate
    when 'queue'
      post_cmd
    when 'result'
      get_cmd
    else
      raise "No this operate: #{@operate}"
    end
  end
end
