# SPDX-License-Identifier: MulanPSL-2.0+ or GPL-2.0
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

CCI_SRC = ENV['CCI_SRC'] || '/c/compass-ci'
require "#{CCI_SRC}/lib/constants.rb"

require 'elasticsearch'
require 'time'
require_relative 'conf'

class Serviceslogs
  include Services

  def initialize
    now = Time.now
    @five_day_ago = (now - 3600 * 24 * 5).strftime('%Y-%m-%d %H:%M:%S')
    @one_day_ago = (now - 3600 * 24).strftime('%Y-%m-%d %H:%M:%S')
    @today = now.strftime('%Y-%m-%d %H:%M:%S')
    @logging_es = Elasticsearch::Client.new hosts: LOGGING_ES_HOSTS
    @time_24h = Time.parse(@one_day_ago).to_i

    @query_result = {
      'total' => 0,
      'cols' => %w[first_date service count error_message],
      'filter' => { 'start_time' => @one_day_ago, 'end_time' => @today },
      'data' => []
    }
  end

  def active_service_logs
    Services::SERVICE.each do |e|
      five_days_results = query_five_service_result(e)
      search_active_error(five_days_results) unless five_days_results.empty?
    end
    @query_result['data'].sort_by! { |e| [e['service'], e['first_date']] }
    @query_result['data'].reverse!
    @query_result['total'] = @query_result['data'].size
    @query_result.to_json
  end

  private

  def query_five_service_result(service_name)
    five_days_results = {}
    query = {
      'size' => 10000,
      'query' => {
        'bool' => {
          'must' => [
            { 'range' => { 'level_num' => { 'gte' => 4 } } },
            { 'range' => { 'time' => { 'gte' => @five_day_ago, 'lte' => @today, 'format' => 'yyyy-MM-dd HH:mm:ss' } } }
          ]
        }
      },
      'sort' => {
        'time' => { 'order' => 'desc' }
      }
    }

    result = @logging_es.search(index: "#{service_name}*", body: query)
    result['hits']['hits'].each do |e|
      time = Time.parse(e['_source']['time']).strftime('%Y-%m-%d %H:%M:%S')
      five_days_results.merge!({ time => {
                                 'service' => e['_index'],
                                 'message' => e['_source']['message']
                               } })
    end

    five_days_results
  end

  def ignore_context(msg)
    if msg.eql?('nil') || msg.nil?
      return ''
    end

    msg.gsub!(/\n.+/, ' ')
    msg.strip!
    msg = $1 if msg =~ %r{(check /[^/]+/[^/]+)} # "check /result/openeuler_docker/2021-06-25/vm-2p16g" => "check /result/openeuler_docker"
    msg.gsub!(/-[0-9]+/, '') # "/c/lkp-tests/stats/install-iso-pre-20210626080006 doesn't exist"
    msg.gsub!(/(z9|crystal)\.[0-9]+/, '')
    msg
  end

  def search_active_error(five_days_results)
    active_results = {}
    five_days_results.each do |k, v|
      time = k
      msg = ignore_context(v['message'])
      next if msg.empty?

      # inside 24h active: { message => {count: 0 , first_date: 0} }
      if Time.parse(time).to_i >= @time_24h
        if active_results.keys.include?(msg)
          active_results[msg]['count'] += 1
        else
          active_results.merge!({ msg => { 'count' => 1, 'first_date' => time, 'service' => v['service'] } })
        end

        active_results[msg]['first_date'] = time
        next
      end

      if active_results.keys.include?(msg)
        active_results[msg]['first_date'] = time
      end
    end

    # generate web data format
    active_results.each do |k, v|
      @query_result['data'] << {
        'first_date' => Time.parse(v['first_date']).strftime('%Y-%m-%d'),
        'service' => v['service'],
        'count' => v['count'],
        'error_message' => k
      }
    end
  end
end

def active_service_error_log
  begin
    body = Serviceslogs.new.active_service_logs
  rescue StandardError => e
    warn e.message
    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), 'get error_message error']
  end

  [200, headers.merge('Access-Control-Allow-Origin' => '*'), body]
end
