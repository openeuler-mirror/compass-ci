# SPDX-License-Identifier: MulanPSL-2.0+ or GPL-2.0
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'elasticsearch'
require_relative 'constants.rb'

# build multiple query request body
class ESQuery
  HOST = (ENV.key?('ES_HOST') ? ENV['ES_HOST'] : ES_HOST)
  PORT = (ENV.key?('ES_PORT') ? ENV['ES_PORT'] : ES_PORT).to_i
  def initialize(host = HOST, port = PORT, index: 'jobs')
    @index = index
    @scroll_id = ''
    @client = Elasticsearch::Client.new url: "http://#{host}:#{port}"
    raise 'Connect Elasticsearch  error!' unless @client.ping
  end

  # Example @items: { key1 => value1, key2 => [value2, value3, ..], ...}
  # means to query: key1 == value1 && (key2 in [value2, value3, ..])
  def multi_field_query(items, size: 10_000)
    unless items
      warn 'empty filter!'
      exit
    end
    query_fields = build_multi_field_subquery_body items
    query = {
      query: {
        bool: {
          must: query_fields
        }
      }, size: size
    }
    @client.search index: @index + '*', body: query
  end

  def traverse_field(size)
    if @scroll_id.empty?
      query = {
        query: {
          bool: {
            must: {
              match_all: {}
            }
          }
        }, size: size
      }
      result = @client.search index: @index, scroll: '10m', body: query
      @scroll_id = result['_scroll_id']
      return result
    else
      @client.scroll scroll: '10m', scroll_id: @scroll_id
    end
  end

  def query_by_id(id)
    result = @client.search(index: @index + '*',
                            body: { query: { bool: { must: { term: { '_id' => id } } } },
                                    size: 1 })['hits']['hits']
    return nil unless result.size == 1

    return result[0]['_source']
  end

  # select doc_field from index
  # input:
  #   eg: suite (@index: jobs)
  # output:
  #   [
  #     {"key"=>"build-pkg", "doc_count"=>90841},
  #     {"key"=>"cci-depends", "doc_count"=>4636},
  #     {"key"=>"cci-makepkg", "doc_count"=>3647},
  #     ...
  #   ]
  def query_specific_fields(field)
    query = {
      aggs: {
        "all_#{field}" => {
          terms: { field: field, size: 1000 }
        }
      },
      size: 0
    }
    result = @client.search(index: @index + '*', body: query)['aggregations']["all_#{field}"]['buckets']
    return nil if result.empty?

    result
  end
end

# Range Query Example:
# range = {
#   start_time: {
#     gte: '2020-09-10 01:50:00',
#     lte: '2020-09-10 01:53:00'
#   },
#   end_time: {
#     gt: '2020-09-10 01:52:00',
#     lt: '2020-09-10 01:54:00'
#   }
# }
# items['range'] = range
def build_multi_field_subquery_body(items)
  query_fields = []
  items.each do |key, value|
    if value.is_a?(Array)
      inner_query = build_multi_field_or_query_body(key, value)
      query_fields.push({ bool: { should: inner_query } })
    elsif key.to_s == 'range'
      query_fields.concat(value.map { |k, v| { range: { k => v } } })
    else
      query_fields.push({ term: { key => value } })
    end
  end
  query_fields
end

def build_multi_field_or_query_body(field, value_list)
  inner_query = []
  value_list.each do |inner_value|
    inner_query.push({ term: { field => inner_value } })
  end
  inner_query
end

def parse_conditions(items)
  items_hash = {}
  items.each do |i|
    key, value = i.split('=')
    if key && value
      value_list = value.split(',')
      items_hash[key] = value_list.length > 1 ? value_list : value
    else
      warn "error: condition \"#{key}\" missing", "tips: should give the input like \"#{key}=value\" "
      exit
    end
  end
  items_hash
end
