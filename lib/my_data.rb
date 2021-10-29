# SPDX-License-Identifier: MulanPSL-2.0+ or GPL-2.0
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'elasticsearch'
require_relative 'constants.rb'

# get data from es logging-es etcd redis ...
class MyData
  def initialize
    @es = Elasticsearch::Client.new hosts: ES_HOSTS
    raise 'Connect es  error!' unless @es.ping

    @logging_es = Elasticsearch::Client.new hosts: LOGGING_ES_HOSTS
    raise 'Connect logging es error!' unless @logging_es.ping
  end

  def get_physical_queues
    [
      'taishan200-2280-2s64p-256g',
      'taishan200-2280-2s64p-128g',
      'taishan200-2280-2s48p-512g',
      'taishan200-2280-2s48p-256g',
      '2288hv5-2s44p-384g'
    ]
  end

  def get_dc_queues(arch)
    queues = [
      'dc-1g',
      'dc-2g',
      'dc-4g',
      'dc-8g',
      'dc-16g',
      'dc-32g'
    ]
    queues.map { |item| item + ".#{arch}" }
  end

  def get_vm_queues(arch)
    queues = [
      'vm-1p1g',
      'vm-2p1g',
      'vm-2p4g',
      'vm-2p8g',
      'vm-2p16g',
      'vm-2p32g'
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

  def logging_es_query(index, query)
    @logging_es.search(index: index + '*', body: query)
  end

  def get_srpm_info(size: 10, from: 0)
    from = from * size
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

    body['OS'].each do |x| os_list << x['key'] end
    body['Type'].each do |x| type_list << x['key'] end
    body['Arch'].each do |x| arch_list << x['key'] end

    data = {
      'OS' => os_list,
      'Type' => type_list,
      'Arch' => arch_list
    }

    JSON.dump data
  end

  def aggs_query(field)
      {
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
