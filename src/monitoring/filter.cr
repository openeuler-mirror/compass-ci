require "set"
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

  def send_msg(query, msg)
    return unless @hash[query]?
    @hash[query].each do |socket|
      socket.send msg.to_json
    end
  end

  def filter_msg(msg)
    msg = JSON.parse(msg.to_s).as_h?
    return unless msg
    @hash.keys.each do |query|
      if match_query(query.as_h, msg)
        send_msg(query, msg)
      end
    end
  end

  def match_query(query : Hash(String, JSON::Any), msg : Hash(String, JSON::Any))
    query_set = query.to_a.to_set
    msg_set = msg.to_a.to_set
    query_set.subset?(msg_set)
  end

end
