# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require 'rest-client'

# mail client class
class MailClient
  HOST = (ENV.key?('MAIL_HOST') ? ENV['MAIL_HOST'] : '127.0.0.1')
  PORT = (ENV.key?('MAIL_PORT') ? ENV['MAIL_PORT'] : 8101).to_i
  def initialize(host = HOST, port = PORT)
    @host = host
    @port = port
  end

  def send_mail(mail_json)
    resource = RestClient::Resource.new("http://#{@host}:#{@port}/send_mail")
    resource.post(mail_json)
  end
end
