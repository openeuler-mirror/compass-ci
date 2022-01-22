# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

CCI_SRC ||= ENV['CCI_SRC'] || '/c/compass-ci'
require 'json'
require 'elasticsearch'
require 'set'
require_relative '../../lib/constants.rb'
require_relative '../../lib/es_query.rb'
require_relative '../../lib/es_client.rb'
require_relative '../../lib/json_logger.rb'

ES_ACCOUNTS = ESQuery.new(index: 'accounts')
REQUIRED_TOKEN_INDEX = Set.new(['jobs'])
UNOPEN_INDEX = Set.new(['accounts'])
ES_QUERY_KEYWORD = Set.new(['term', 'match'])

def es_find(params)
  begin
    result = query_es(params)
  rescue StandardError => e
    log_error({
      'message' => e.message,
      'error_message' => "query es error"
    })
    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), e.message]
  end
  [200, headers.merge('Access-Control-Allow-Origin' => '*'), result.to_json]
end

def query_es(params)
  request_body = JSON.parse(params)
  index = request_body['index'] || 'jobs'
  query = request_body['query'] || {'query' => {}}
  return "#{index} is not opened" if UNOPEN_INDEX.any? { |unopen_index| index.include?(unopen_index) }

  if REQUIRED_TOKEN_INDEX.any? { |req_index| index.include?(req_index) }
    my_account = request_body['my_account']
    my_token = request_body['my_token']
    return "missed my_account" unless my_account
    return "missed my_token" unless my_token
    return "user authentication failed" unless verify_user(my_account, my_token)

    query = build_account_query(query, my_account, request_body['query_type'], index)
  end

  if request_body['query_type'] == 'sql'
    es = ESClient.new(index: index)
    return es.query_by_sql(query).body
  else
    es = Elasticsearch::Client.new(hosts: ES_HOSTS)
    return es.search index: index + '*', body: query
  end
end

def verify_user(my_account, my_token)
  query = {}
  query['my_account'] = my_account if my_account
  query['my_token'] = my_token if my_token

  result = ES_ACCOUNTS.multi_field_query(query)['hits']['hits']
  return nil if result.size == 0

	result[0]['_source']['my_token'] == my_token
end

def build_account_query(query, my_account, query_type, index)
  if query_type == 'sql'
    user_limit = "my_account='#{my_account}'"
    if query =~ /where/i
      query = query.gsub(/FROM\s*\S+/i, "FROM #{index} ")
      query = query.gsub(/where/i, "WHERE #{user_limit} AND")
    else
      query = query.gsub(/from\s*\S+/i, "FROM #{index} WHERE #{user_limit}")
    end
  else
    query['query'] ||= {}
    query['query']['bool'] ||= {}
    query['query']['bool']['must'] ||= []
    query['query']['bool']['must'] << {'term' => {'my_account' => my_account}}

    query['query'].each do |k, v|
      if ES_QUERY_KEYWORD.include?(k)
        query['query']['bool']['must'] << {k => v}
        query['query'].delete(k)
      end
    end
  end

  query
end
