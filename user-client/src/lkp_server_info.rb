require 'net/http'

#
class LkpServerInfo
  attr_accessor :host, :port

  def initialize(host = '127.0.0.1', port = '3000')
    @host = host
    @port = port
  end

  def connect_able
    url = URI("http://#{@host}:#{@port}")
    http = Net::HTTP.new(url.host, url.port)

    begin
      response = http.get(url)
      case response.code
      when '200', '401'
        true
      else
        false
      end
    rescue exception
      false
    end
  end
end
