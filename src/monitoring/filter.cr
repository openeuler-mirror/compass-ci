# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "set"
require "json"

require "./parse_serial_logs"
require "../lib/json_logger"

class Filter
  def initialize
    # use @hash to save query and socket
    # like {query => [socket1, socket2]}
    @hash = Hash(JSON::Any, Array(HTTP::WebSocket)).new
    @sp = SerialParser.new
    @log = JSONLogger.new
  end

  def add_filter_rule(query : JSON::Any, socket : HTTP::WebSocket)
    query = convert_hash_value_to_array(query)

    @hash[query] = Array(HTTP::WebSocket).new unless @hash[query]?
    @hash[query] << socket

    return query
  end

  private def convert_hash_value_to_array(query)
    new_query = Hash(String, Array(JSON::Any)).new

    query.as_h.each do |key, value|
      new_query[key] = value.as_a? || [value]
    end
    JSON.parse(new_query.to_json)
  end

  def remove_filter_rule(query : JSON::Any, socket : HTTP::WebSocket)
    return unless @hash[query]?

    @hash[query].delete(socket)
    @hash.delete(query) if @hash[query].empty?
  end

  def send_msg(query, msg)
    return unless @hash[query]?

    @hash[query].each do |socket|
      socket.send msg.to_json
    rescue e
      @log.warn("send msg failed: #{e}")
      remove_filter_rule(query, socket)
    end
  end

  def filter_msg(msg)
    msg = JSON.parse(msg.to_s).as_h?
    return unless msg

    @sp.save_dmesg_to_result_root(msg)
    @hash.keys.each do |query|
      if match_query(query.as_h, msg)
        send_msg(query, msg)
      end
    end
  end

  def match_query(query : Hash(String, JSON::Any), msg : Hash(String, JSON::Any))
    query.each do |key, value|
      key = find_real_key(key, msg.keys) unless msg.has_key?(key)
      return false unless key

      values = value.as_a
      next if values.includes?(nil) || values.includes?(msg[key]?)

      return false unless regular_match(values, msg[key]?.to_s)
    end
    return true
  end

  private def find_real_key(rule, keys)
    keys.each do |key|
      return key if key.to_s =~ /#{rule}/
    end
  end

  private def regular_match(rules, string)
    rules.each do |rule|
      return true if string =~ /#{rule}/
    end
    return false
  end
end
