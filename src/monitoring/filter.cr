require "json"

class Filter

  def initialize()
    # use @hash to save query and socket
    # like {query => [socket1, socket2]}
    @hash = Hash(JSON::Any, Array(HTTP::WebSocket)).new
  end

  def add_filter_rule(query : JSON::Any, socket : HTTP::WebSocket)
    @hash[query] = Array(HTTP::WebSocket).new unless @hash[query]?
    @hash[query] << socket
  end

  def remove_filter_rule(query : JSON::Any, socket : HTTP::WebSocket)
    return unless @hash[query]?
    @hash[query].delete(socket)
  end

end
