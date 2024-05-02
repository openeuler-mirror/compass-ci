# SPDX-License-Identifier: MulanPSL-2.0+ or GPL-2.0
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'elasticsearch'
require_relative 'constants.rb'

# build multiple query request body
class ESQuery
  def initialize(hosts=ES_HOSTS, index: 'jobs')
    @hosts = hosts
    @index = index
    @scroll_id = ''
    @client = Elasticsearch::Client.new hosts: hosts
    raise 'Connect Elasticsearch  error!' unless @client.ping
  end

  def run_curl(args)
    @hosts.each do |host|
      cmd = ["curl", '-u', host[:user] + ':' + host[:password], '-X', args[0], "#{host[:host]}:#{host[:port]}#{args[1]}"]
      system(*cmd)
    end
  end

  def query_json(query)
    @client.search index: @index + '*', body: query
  end

  # Example @items: { key1 => value1, key2 => [value2, value3, ..], ...}
  # Example @unmatch_items: { key1 => value1, key2 => [value2, value3, ..], ...}
  # means to query: key1 == value1 && (key2 in [value2, value3, ..])
  def multi_field_query(items, unmatch_items: {}, size: 10_000, desc_keyword: nil, regexp: nil, single_index: false)
    unless items
      warn 'empty filter!'
      exit
    end
    query_fields = build_multi_field_subquery_body(items, regexp)
    unmatch_fields = build_multi_field_subquery_body unmatch_items
    query = {
      query: {
        bool: {
          must: query_fields,
          must_not: unmatch_fields
        }
      }, size: size
    }
    query.merge!(assign_desc_body(desc_keyword)) if desc_keyword
    if single_index
      @client.search index: @index, body: query
    else
      @client.search index: @index + '*', body: query
    end
  end

  # usage is the same as multi_field_query,
  # but the function can request large data sets that more than index.max_result_window(default 10_000).
  def multi_field_scroll_query(items, unmatch_items: {}, desc_keyword: nil)
    unless items
      warn 'empty filter!'
      exit
    end
    query_fields = build_multi_field_subquery_body items
    unmatch_fields = build_multi_field_subquery_body unmatch_items
    query = {
      query: {
        bool: {
          must: query_fields,
          must_not: unmatch_fields
        }
      }
    }
    query.merge!(assign_desc_body(desc_keyword)) if desc_keyword

    result = @client.search index: @index + '*', scroll: '10m', body: query
    jobs = []
    @scroll_id = result['_scroll_id'] unless result.empty? && result.include?('_scroll_id')

    while result['hits']['hits'].size.positive?
      jobs += result['hits']['hits']
      result = @client.scroll scroll: '10m', scroll_id: @scroll_id
    end

    @client.clear_scroll scroll_id: @scroll_id

    return jobs
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
    else
      result = @client.scroll scroll: '10m', scroll_id: @scroll_id
    end

    @scroll_id = result['_scroll_id'] unless result.empty? && result.include?('_scroll_id')
    return result
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
          terms: { field: field, size: 10000 }
        }
      },
      size: 0
    }
    result = @client.search(index: @index + '*', body: query)['aggregations']["all_#{field}"]['buckets']
    return nil if result.empty?

    result
  end

  # input:
  #   fields, query_items
  #
  #   fields => fields: Array(keyword)
  #   eg:
  #     ['suite', 'job_state']
  #
  #   query_items => query_items: Hash(keyword, value)
  #   eg:
  #     {
  #       'os' => 'openeuler',
  #       ...
  #     }
  #   (optional for query_items, default no scope limitation)
  # output:
  #   [{"key"=>"build-pkg",
  #     "doc_count"=>186175,
  #     "all_job_state"=>
  #      {"doc_count_error_upper_bound"=>0,
  #       "sum_other_doc_count"=>0,
  #       "buckets"=>
  #        [{"key"=>"failed", "doc_count"=>3830},
  #         {"key"=>"finished", "doc_count"=>803},
  #         {"key"=>"incomplete", "doc_count"=>196},
  #         ...
  def query_fields(fields, query_items = {})
    field1 = fields.first
    aggs_hash = build_aggs_from_fields(fields)
    query = {
      query: {
        bool: {
          must: build_multi_field_subquery_body(query_items)
        }
      },
      aggs: aggs_hash['aggs'],
      size: 0
    }
    result = @client.search(index: @index + '*', body: query)['aggregations']["all_#{field1}"]['buckets']
    return nil if result.empty?

    parse_fields(result)
  end

  def query_mapping
    mapping = @client.indices.get_mapping(index: @index)
    get_mapping_key(mapping)
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
def build_multi_field_subquery_body(items, regexp = nil)
  query_fields = []
  items.each do |key, value|
    if value.is_a?(Array)
      inner_query = build_multi_field_or_query_body(key, value, regexp)
      query_fields.push({ bool: { should: inner_query } })
    elsif key.to_s == 'range'
      query_fields.concat(value.map { |k, v| { range: { k => v } } })
    else
      if regexp
        query_fields.push({ regexp: { key => ".*#{value}.*" } })
      else
        query_fields.push({ term: { key => value } })
      end
    end
  end
  query_fields
end

def build_multi_field_or_query_body(field, value_list, regexp)
  inner_query = []
  value_list.each do |inner_value|
    if regexp
      inner_query.push({ regexp: { field => ".*#{inner_value}.*" } })
    else
      inner_query.push({ term: { field => inner_value } })
    end
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

def assign_desc_body(keyword)
  {
    sort: [{
      keyword => { order: 'desc' }
    }]
  }
end

# input:
#   fields = ['os', 'os_version', 'job_state']
# output:
#   aggs_hash = {
#     "aggs"=>
#      {"all_os"=>
#        {"terms"=>{:field=>"os", :size=>1000},
#         "aggs"=>
#          {"all_os_version"=>
#            {"terms"=>{:field=>"os_version", :size=>1000},
#             "aggs"=>
#              {"all_job_state"=>{"terms"=>{:field=>"job_state", :size=>1000}}}}}}}
#   }
def build_aggs_from_fields(fields)
  aggs_hash = {}
  return if fields.empty?

  field = fields.shift
  aggs_hash['aggs'] ||= {}
  aggs_hash['aggs']["all_#{field}"] = {
    'terms' => { field: field, size: 10000 }
  }
  sub_aggs = build_aggs_from_fields(fields)
  aggs_hash['aggs']["all_#{field}"].merge!(sub_aggs) if sub_aggs
  aggs_hash
end

# input:
#   es_result =
#     [{"key"=>"build-pkg",
#       "doc_count"=>354526,
#       "all_job_state"=>
#        {"doc_count_error_upper_bound"=>0,
#         "sum_other_doc_count"=>0,
#         "buckets"=>
#          [{"key"=>"failed", "doc_count"=>5708},
#           {"key"=>"finished", "doc_count"=>1033},
#           {"key"=>"incomplete", "doc_count"=>204},
#           {"key"=>"submit", "doc_count"=>136},
#           ...
#
# output:
#   result_hash =
#     {"build-pkg"=>
#       {"failed"=>5708,
#        "finished"=>1033,
#        "incomplete"=>204,
#        "submit"=>136,
#        "OOM"=>11,
#        "post_run"=>2},
#      "cci-depends"=>
#       {"finished"=>1785,
#        "failed"=>675,
#        ...
def parse_fields(es_result)
  result_hash = {}
  es_result.each do |result|
    key = result['key']
    sub_field = result.keys.detect { |field| field.start_with?('all_') }

    if sub_field
      all_field = result[sub_field]['buckets']
      result_hash[key] = parse_fields(all_field)
    else
      result_hash[key] = result['doc_count']
    end
  end

  result_hash
end

def get_mapping_key(mapping)
  mapping_key = []
  properties = mapping.values[0]['mappings']['properties']
  properties.each do |key, value|
    parse_mapping_properties(key, value, mapping_key)
  end

  mapping_key
end

def parse_mapping_properties(key, value, mapping_key)
  if value['type']
    mapping_key << {'type' => value['type'], 'key' => key}
  else
    value['properties'].each do |k, v|
      parse_mapping_properties("#{key}.#{k}", v, mapping_key)
    end
  end
end
