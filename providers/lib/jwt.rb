#!/usr/bin/env ruby

require 'yaml'
require 'json'
require 'fileutils'
require 'openssl'
require 'net/http'
require 'base64'

require_relative '../../container/defconfig'
require_relative "remote_client"


def load_my_config
  account_conf = Set.new %w[
   ACCOUNT
   PASSWORD
   OAUTH_TOKEN_URL
   OAUTH_REDIRECT_URL
   PUBLIC_KEY_URL
   DOMAIN_NAME
  ]
  config =  relevant_service_authentication(account_conf)
  return config
end

def encrypt_password(password, public_key_url)
  url = URI.parse(public_key_url)
  response = Net::HTTP.get_response(url)
  public_key_string = JSON.parse(response.body)['data']['rsa']['publicKey']

  rsa = OpenSSL::PKey::RSA.new public_key_string
  Base64.encode64(rsa.public_encrypt password).gsub!("\n", '')
end

def load_jwt?(force_update=false)
  begin
    local_jwt = File.read("/tmp/#{ENV['HOSTNAME']}/jwt")
  rescue Errno::ENOENT => e
    local_jwt = nil
  end
  if local_jwt.nil? or force_update
    config = load_my_config
    password = encrypt_password(config['PASSWORD'], config['PUBLIC_KEY_URL'])
    api_client = RemoteClient.new()
    response = api_client.get_client_info(config['DOMAIN_NAME'])
    response = JSON.parse(response)
    client_id = response['client_id'].strip
    client_secret = response['client_secret'].strip
    out_str = %x(curl -s -X POST --data-urlencode "grant_type=password" \
--data-urlencode "account=#{config['ACCOUNT']}" --data-urlencode "password=#{password}" \
--data-urlencode "client_id=#{client_id}" --data-urlencode "client_secret=#{client_secret}" \
--data-urlencode "redirect_uri=#{config['OAUTH_REDIRECT_URL']}" "#{config['OAUTH_TOKEN_URL']}")
    puts out_str
    out_hash = JSON.parse(out_str)
    if out_hash.has_key?('error')
      puts "get access token failed"
      access_token = nil
    else
      access_token = out_hash['access_token']
    end
    if access_token.nil?
      return nil
    end
    api_client = RemoteClient.new()
    response = api_client.get_jwt(access_token, config['DOMAIN_NAME'])
    response = JSON.parse(response)
    if response.has_key?('token')
      FileUtils.mkdir_p "/tmp/#{ENV['HOSTNAME']}" unless File.directory? "/tmp/#{ENV['HOSTNAME']}"
      aFile = File.new("/tmp/#{ENV['HOSTNAME']}/jwt", "w+")
      if aFile
        aFile.syswrite(response['token'])
      else
        puts 'save jwt faild'
      end
      return response['token']
    else
      return nil
    end
  else
    return local_jwt
  end
end

def check_return_code(response)
  status_code_array = [401, 403, 404]
  if response.has_key?('status_code') && status_code_array.include?(response['status_code'])
    case response['status_code']
    when 401
      puts 'Jwt has expired'
    when 403
      puts 'Please register account first'
    when 404
      puts "Url not found: #{response['url']}"
    end
    exit
  end
end
