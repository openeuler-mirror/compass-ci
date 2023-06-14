# SPDX-License-Identifier: MulanPSL-2.0+ or GPL-2.0
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'elasticsearch'

require_relative 'utils.rb'
require_relative 'constants.rb'

# get data from es logging-es etcd redis ...
class MyData
  def initialize
    @es = Elasticsearch::Client.new hosts: ES_HOSTS
    raise 'Connect es  error!' unless @es.ping
  end

  def get_physical_queues
    %w[
      taishan200-2280-2s64p-256g
      taishan200-2280-2s64p-128g
      taishan200-2280-2s48p-512g
      taishan200-2280-2s48p-256g
      2288hv5-2s44p-384g
    ]
  end

  def get_dc_queues(arch)
    queues = %w[
      dc-1g
      dc-2g
      dc-4g
      dc-8g
      dc-16g
      dc-32g
    ]
    queues.map { |item| item + ".#{arch}" }
  end

  def get_vm_queues(arch)
    queues = %w[
      vm-1p1g
      vm-2p1g
      vm-2p4g
      vm-2p8g
      vm-2p16g
      vm-2p32g
    ]
    queues.map { |item| item + ".#{arch}" }
  end

  def get_public_queues(type, arch)
    case type
    when 'physical'
      return get_physical_queues
    when 'dc'
      return get_dc_queues(arch)
    when 'vm'
      return get_vm_queues(arch)
    else
      return []
    end
  end

  def testbox_info(body)
    all = {}
    total = JSON.parse(body)['total']
    all.store('total', total)
    info = []
    JSON.parse(body)['data']['hits']['hits'].each do |source|
      tmp_hash = {}

      tmp_hash['testbox'] = source['_source']['name']
      tmp_hash['state'] = source['_source']['state']
      tmp_hash['arch'] = source['_source']['arch']
      tmp_hash['job_id'] = source['_source']['job_id']
      tmp_hash['user'] = source['_source']['my_account']
      tmp_hash['time'] = source['_source']['time']
      tmp_hash['suite'] = source['_source']['suite']
      tmp_hash['tbox_group'] = source['_source']['tbox_group']
      tmp_hash['queues'] = source['_source']['queues']
      info.append(tmp_hash)
    end
    all.store('info', info)

    return all
  end

  def testbox_status(params, type: 'physical')
    result = {}
    running_physical = testbox_status_query(params, type: type, time1: '180d', state: ['running', 'requesting', 'rebooting', 'booting', 'rebooting_queue'])

    result = testbox_info(running_physical)

    return  result
  end

  def testbox_status_query(params, type: 'physical', time1: '30m', time2: 'now', state: 'requesting')
    page_size = get_positive_number(params.delete(:page_size), 10)
    page_num = get_positive_number(params.delete(:page_num), 1) - 1
    check_es_size_num(page_size, page_num)
    from = page_num * page_size

    total_query =  query = {
      'size' => page_size,
      'from' => from,
      'query' => {
        'bool' => {
          'must' => [
            {
              'term' => {
                'type' => { 'value' => type }
              }
            },
            {
              'terms' => {
                'state' => state
              }
            },
            {
              'range' => {
                'time' => {
                  'gte' => 'now-' + time1,
                  'lte' => time2
                }
              }
            }
          ]
        }
      }
    }
    params.each do |k, v|
      next if k == 'type'
      next if v.empty?
      items = {
        'terms' => {
          "#{k}.keyword" => v
        }
      }
      query['query']['bool']['must'].append(items)
    end
    data = es_query('testbox', query)
    total_query.delete('from')
    total_query.delete('size')
    total = @es.count(index: 'testbox', body: total_query)['count']
    {

      total: total,
      data: data
    }.to_json
  end

  def query_testbox_list(params)
    type = params['type'] || 'physical'
    body = {
      'Arch' => es_query('testbox', aggs_query_(type, 'arch'))['aggregations']['all_arch']['buckets'],
      'State' => es_query('testbox', aggs_query_(type, 'state'))['aggregations']['all_state']['buckets'],
      'User' => es_query('testbox', aggs_query_(type, 'my_account'))['aggregations']['all_my_account']['buckets'],
      'TboxGroup' => es_query('testbox', aggs_query_(type, 'tbox_group'))['aggregations']['all_tbox_group']['buckets']
    }

    arch_list = []
    state_list = []
    user_list = []
    tbox_group_list = []

    body['Arch'].each { |x| arch_list << x['key'] if x['key'].size.to_i > 0 }
    body['State'].each { |x| state_list << x['key'] if x['key'].size.to_i > 0 }
    body['User'].each { |x| user_list << x['key'] if x['key'].size.to_i > 0 }
    body['TboxGroup'].each { |x| tbox_group_list << x['key'] if x['key'].size.to_i > 0 }

    data = {
      'Arch' => arch_list,
      'State' => state_list,
      'User' => user_list,
      'TboxGroup' => tbox_group_list
    }

    return data
  end

  def get_testbox_aggs(type: 'physical', time1: '30m', time2: 'now', size: 0, state: 'requesting', arch: 'aarch64')
    queues = get_public_queues(type, arch)

    query = {
      'size' => size,
      'query' => {
        'bool' => {
          'must' => [
            {
              'terms' => {
                'queues.keyword' => queues
              }
            },
            {
              'term' => {
                'type' => { 'value' => type }
              }
            },
            {
              'term' => {
                'arch' => { 'value' => arch }
              }
            },
            {
              'term' => {
                'state' => { 'value' => state }
              }
            },
            {
              'range' => {
                'time' => {
                  'gte' => 'now-' + time1,
                  'lte' => time2
                }
              }
            }
          ]
        }
      },
      'aggs' => {
        'queue' => {
          'terms' => {
            'field' => 'tbox_group.keyword'
          }
        }
      }
    }
    es_query('testbox', query)
  end

  def es_query(index, query)
    @es.search(index: index + '*', body: query)
  end

  def es_search_all(index, query)
    result = @es.search index: index, scroll: '10m', body: query
    results = []
    scroll_id = result['_scroll_id'] unless result.empty? && result.include?('_scroll_id')

    while result['hits']['hits'].size.positive?
      results += result['hits']['hits']
      result = @es.scroll scroll: '10m', scroll_id: scroll_id
    end

    return results
  end

  def es_delete(index, id)
    @es.delete(index: index, 'id': id)
  end

  def es_update(index, id, data)
    @es.update(index: index, 'id': id, body: { doc: data })
  end

  def es_add(index, id, data)
    @es.index(index: index, 'id': id, body: data)
  end

  def get_srpm_info(size: 10, from: 0)
    from *= size
    query = {
      'size' => size,
      'from' => from
    }
    es_query('srpm-info', query)
  end

  def query_compat_software
    body = {
      'OS' => es_query('compat-software-info', aggs_query('os'))['aggregations']['all_os']['buckets'],
      'Type' => es_query('compat-software-info', aggs_query('type'))['aggregations']['all_type']['buckets'],
      'Arch' => es_query('compat-software-info', aggs_query('arch'))['aggregations']['all_arch']['buckets']
    }

    os_list = []
    type_list = []
    arch_list = []

    body['OS'].each { |x| os_list << x['key'] if x['key'].size.to_i > 0 }
    body['Type'].each { |x| type_list << x['key'] if x['key'].size.to_i > 0 }
    body['Arch'].each { |x| arch_list << x['key'] if x['key'].size.to_i > 0 }

    data = {
      'OS' => os_list,
      'Type' => type_list,
      'Arch' => arch_list
    }

    return data
  end

  def aggs_query(field)
    {
      'aggs' => {
        "all_#{field}" => {
          'terms' => {
            'field' => field.to_s,
            'size' => '10000'
          }
        }
      }
    }
  end

  def aggs_query_(type, field)
    {
      'query' => {
        'bool' => {
          'must' => [
            'term' => {
              'type' => {'value' => type }
            }
          ]
        }
      },
      'aggs' => {
        "all_#{field}" => {
          'terms' => {
            'field' => "#{field}.keyword",
            'size' => '10000'
          }
        }
      }
    }
  end
end
