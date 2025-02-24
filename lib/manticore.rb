# lib/manticore.rb
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'time'
require_relative './constants-job.rb'

module Manticore
  HOST = ENV['MANTICORE_HOST'] || 'localhost'
  PORT = ENV['MANTICORE_PORT'] || 9308
  DEFAULT_INDEX = 'jobs'

  def self.filter_sql_fields(sql)
    sql.gsub(/\b(#{MANTI_JSON_PROPERTIES.join('|')})\b/, 'j.\1').gsub(/j\.j\./, 'j.')
  end

  def self.filter_sql_result(body)
    body.gsub(/"j.([^" ]+)":/, '"\1":')
  end

  class Client
    # return format is [{ "columns": [{}...], "data": [{}...]}, "total": N }]
    def self.execute_sql(sql)
      uri = URI("http://#{HOST}:#{PORT}/sql")
      request = Net::HTTP::Post.new(uri)
      request.body = "mode=raw&query=#{URI.encode_www_form_component(sql)}"
      response = Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(request) }
      # result_hash = JSON.parse(response.body.gsub(/"j.([^" ]+)":/, '"\1":'))
    end

    # return format is "hits": { "hits": [ { "_source": {job hash}}]}
    def self.execute_select(sql)
      uri = URI("http://#{HOST}:#{PORT}/sql")
      request = Net::HTTP::Post.new(uri)
      request.body = "query=#{URI.encode_www_form_component(sql)}"
      response = Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(request) }
      # result_hash = JSON.parse(response.body)
    end

    # return format is "hits": { "hits": [ { "_source": {job hash}}]}
    def self.search(query)
      uri = URI("http://#{HOST}:#{PORT}/search")
      response = Net::HTTP.post(uri, query.to_json, 'Content-Type' => 'application/json')
      # result_hash = JSON.parse(response.body)
    end

  end

  class QueryBuilder
    def initialize(index: DEFAULT_INDEX, size: 10)
      @index = index
      @size = size
      @full_text_terms = {}
      @equals_clauses = []
      @ranges = {}
      @sort = {}
    end

    def add_filter(field, values)
      if MANTI_JSON_PROPERTIES.include?(field)
        @full_text_terms[:full_text_kv] ||= []
        @full_text_terms[:full_text_kv] += values.map { |v| "#{field}=#{v}" }
      elsif field == 'errid'
        @full_text_terms[:errid] ||= []
        @full_text_terms[:errid] += values.map { |v| v.to_s }
      else
        @equals_clauses += values.map do |v|
          v = convert_value(v)
          { equals: { field => v } }
        end
      end
    end

    def add_range(field, gte: nil, lte: nil)
      @ranges[field] = { gte: gte, lte: lte }.compact
    end

    def sort(field, order: 'desc')
      @sort[field] = order
    end

    def build
      query = { index: @index, limit: @size }
      bool = { must: [] }

      bool[:must] << { match: @full_text_terms } unless @full_text_terms.empty?
      bool[:must] += @equals_clauses unless @equals_clauses.empty?
      
      @ranges.each do |field, range|
        bool[:must] << { range: { field => range } }
      end

      query[:query] = { bool: bool } unless bool[:must].empty?
      query[:sort] = [@sort] unless @sort.empty?

      query
    end

    private

    def convert_value(value)
      case value
      when /^\d+$/ then value.to_i
      when /^\d+\.\d+$/ then value.to_f
      else value
      end
    end
  end

  module TimeParser
    def self.parse_range(ranges)
      range_hash = {}
      ranges.each do |keyword|
        key, value = keyword.split('=')
        key, value = expand_shortcut_syntax(key, value)
        check_range_args(key, value)
        range_hash[key] = assign_range(value)
      end
      range_hash
    end

    private

    def self.expand_shortcut_syntax(key, value)
      if key =~ /^(\+)?([0-9]+d)$/
        [key, shortcut_value($1, $2)]
      elsif value =~ /^(\+?)([0-9]+d)$/
        [key, shortcut_value($1, $2)]
      else
        [key, value]
      end
    end

    def self.shortcut_value(prefix, days)
      value = "now-#{days}"
      prefix == "+" ? ",#{value}" : value
    end

    def self.check_range_args(key, value)
      return if key && value
      warn "ERROR: Invalid range format. Use: field=start,end or field=3d"
      exit 1
    end

    def self.assign_range(value)
      from, to = value.split(',')
      range = {}
      range[:gte] = parse_time(from) if present?(from)
      range[:lte] = parse_time(to) if present?(to)
      range
    end

    def self.parse_time(time_spec)
      return Time.now.to_i - (time_spec.to_i * 86400) if time_spec.match?(/^\d+d$/)
      Time.parse(time_spec).to_i
    rescue ArgumentError
      nil
    end

    def self.present?(str)
      str && !str.empty?
    end
  end
end
