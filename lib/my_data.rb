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

  def get_public_queues(type)
    case type
    when 'physical'
      queues = [
        'taishan200-2280-2s64p-256g',
        'taishan200-2280-2s48p-512g',
        'taishan200-2280-2s48p-256g',
        '2288hv5-2s44p-384g'
      ]
    when 'dc'
      queues = [
        'dc-1g.aarch64',
        'dc-2g.aarch64',
        'dc-4g.aarch64',
        'dc-8g.aarch64',
        'dc-16g.aarch64',
        'dc-32g.aarch64'
      ]
    when 'vm'
      queues = [
        'vm-1p1g.aarch64',
        'vm-2p1g.aarch64',
        'vm-2p4g.aarch64',
        'vm-2p8g.aarch64',
        'vm-2p16g.aarch64',
        'vm-2p32g.aarch64'
      ]
    else
      queues = []
    end

    queues
  end

  def get_testbox_aggs(type: 'physical', time1: '30m', time2: 'now', size: 0, state: 'requesting')
    queues = get_public_queues(type)

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
end
