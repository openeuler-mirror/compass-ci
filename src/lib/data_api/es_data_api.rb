# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

CCI_SRC ||= ENV['CCI_SRC'] || '/c/compass-ci'
require 'json'
require 'set'
require "#{CCI_SRC}/lib/constants.rb"
require "#{CCI_SRC}/lib/es_client.rb"

# this module is for es api
# - search
# - opendistro_sql(search by sql)
module EsDataApi
  ES_ACCOUNTS = ESClient.new(index: 'accounts')
  OPEN_INDEX = Set.new(['jobs'])
  REQUIRED_TOKEN_INDEX = Set.new(['jobs'])
  ES_QUERY_KEYWORD = Set.new(%w[term match])

  def self.credentials_for_dsl(query, my_account)
    query['query'] ||= {}
    query['query']['bool'] ||= {}
    query['query']['bool']['must'] ||= []
    query['query']['bool']['must'] << { 'term' => { 'my_account' => my_account } }
    query = handle_dsl_query(query)
    return query
  end

  def self.handle_dsl_query(query)
    query['query'].each do |k, v|
      if ES_QUERY_KEYWORD.include?(k)
        query['query']['bool']['must'] << { k => v }
        query['query'].delete(k)
      end
    end
    return query
  end

  def self.check_my_account(request_body)
    cci_credentials = request_body['cci_credentials'] || {}
    my_account = cci_credentials['my_account']
    my_token = cci_credentials['my_token']
    raise 'user authentication failed, please check my_account and my_token.' unless verify_user(my_account, my_token)

    return my_account
  end

  def self.search(index, params)
    request_body = JSON.parse(params)
    query = request_body['query'] || { 'query' => {} }
    raise "#{index} is not opened for user query" unless OPEN_INDEX.include?(index)

    if REQUIRED_TOKEN_INDEX.include?(index)
      my_account = check_my_account(request_body)
      query = credentials_for_dsl(query, my_account)
    end
    es = Elasticsearch::Client.new(hosts: ES_HOSTS)
    return es.search index: index + '*', body: query
  end

  def self.get_index_from_sql(sql)
    return $1 if sql =~ /from\s+(\S+)\s*/i

    raise 'Can not get query table, please submmit the correct sql query statement'
  end

  def self.credentials_for_sql(query, my_account, index)
    user_limit = "my_account='#{my_account}'"
    if query =~ /where/i
      query = query.gsub(/FROM\s*\S+/i, "FROM #{index} ")
      query = query.gsub(/where/i, "WHERE #{user_limit} AND")
    else
      query = query.gsub(/from\s*\S+/i, "FROM #{index} WHERE #{user_limit}")
    end
    return query
  end

  def self.opendistro_sql(params)
    request_body = JSON.parse(params)
    query = request_body['query']
    index = get_index_from_sql(query)
    raise "#{index} is not opened for user query" unless OPEN_INDEX.include?(index)

    if REQUIRED_TOKEN_INDEX.include?(index)
      my_account = check_my_account(request_body)
      query = credentials_for_sql(query, my_account, index)
    end

    es = ESClient.new(index: index)
    return es.opendistro_sql(query).body
  end

  def self.verify_user(my_account, my_token)
    raise 'missed my_account' unless my_account
    raise 'missed my_token' unless my_token

    query = {}
    query['my_account'] = my_account
    query['my_token'] = my_token

    result = ES_ACCOUNTS.multi_field_query(query)['hits']['hits']
    return nil if result.empty?

    result[0]['_source']['my_token'] == my_token
  end
end
