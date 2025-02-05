# frozen_string_literal: true

require 'rest-client'

# remote multi docker api client class
class RemoteClient
  def initialize(host = '172.17.0.1', port = 10_012)
    @host = host
    @port = port
    @url_prefix = url_prefix
  end

  def get_jwt(access_code, domain)
    # resource = RestClient::Resource.new("#{@url_prefix}#{@host}:#{@port}/api/user_auth/access_code_authorize?access_code=#{access_code}")
    resource = RestClient::Resource.new("https://#{domain}/api/user_auth/access_code_authorize?access_code=#{access_code}")
    resource.get
  end

  def get_client_info(domain)
    # resource = RestClient::Resource.new("#{@url_prefix}#{@host}:#{@port}/api/user_auth/get_client_info")
    resource = RestClient::Resource.new("https://#{domain}/api/user_auth/get_client_info")
    resource.get
  end

  private def url_prefix
    @url_prefix = if @host.match('.*[a-zA-Z]+.*')
                    # Internet users should use domain name and https
                    'https://'
                  else
                    # used in intranet for now
                    'http://'
                  end
  end
end
