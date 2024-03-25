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
  ES_AUTHORIZED = ESClient.new(index: 'authorized')
  # TODO lkp_jobs lkp_programs lkp_workflows之后在远程LAB方案确定后考虑走独立服务获取
  OPEN_INDEX = Set.new(%w[jobs hosts lkp_jobs lkp_programs lkp_workflows])
  REQUIRED_TOKEN_INDEX = Set.new(['jobs'])
  ES_QUERY_KEYWORD = Set.new(%w[term match])

  def self.credentials_for_dsl(query, authorized_accounts)
    query['query'] ||= {}
    query['query']['terms'] ||= {}
    query['query']['terms']['my_account'] = authorized_accounts
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

  def self.get_authorized_accounts(my_account)
    query = {}
    query['my_account'] = my_account

    result = ES_AUTHORIZED.multi_field_query(query, single_index: true)['hits']['hits']
    return [my_account] if result.empty?
    return result[0]['_source']['authorized_accounts'] << my_account
  end

  def self.search(index, params)
    request_body = JSON.parse(params)
    query = request_body['query'] || { 'query' => {} }
    raise "#{index} is not opened for user query" unless OPEN_INDEX.include?(index)

    # need to debug
    # if REQUIRED_TOKEN_INDEX.include?(index)
    #   my_account = check_my_account(request_body)
    #   authorized_accounts = get_authorized_accounts(my_account)
    #   query = credentials_for_dsl(query, authorized_accounts)
    # end
    es = Elasticsearch::Client.new(hosts: ES_HOSTS)
    return es.search index: index + '*', body: query
  end

  def self.join_query_sql(index = nil, field = nil)
    raise 'Can not get query index, please input the correct index' if index.nil?
    raise 'Can not get query field, please input the correct field' if field.nil?
    raise "#{index} is not opened for user query" unless OPEN_INDEX.include?(index)

    "SELECT #{field} FROM #{index}"
  end

  def self.credentials_for_sql(query_sql, request_body)
    query_where = request_body['query_where']
    query_index = request_body['query_index']
    unless REQUIRED_TOKEN_INDEX.include?(query_index)
      query_sql += " WHERE #{query_where}" unless query_where.nil?
      return query_sql
    end

    my_account = check_my_account(request_body)
    authorized_accounts = get_authorized_accounts(my_account)
    user_limit = "my_account IN (" + authorized_accounts.join(',') + ") "
    query_sql += if query_where.nil?
                   " WHERE #{user_limit}"
                 else
                   " WHERE #{user_limit} AND (#{query_where}) "
                 end
    return query_sql
  end

  def self.opendistro_sql(params)
    request_body = JSON.parse(params)
    query_field = request_body['query_field']
    query_index = request_body['query_index']
    query_condition = request_body['query_condition']
    query_sql = join_query_sql(query_index, query_field)
    query_sql = credentials_for_sql(query_sql, request_body)
    query_sql += query_condition unless query_condition.nil?
    es = ESClient.new(index: query_index)
    return es.opendistro_sql(query_sql).body
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
