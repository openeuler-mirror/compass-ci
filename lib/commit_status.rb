# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require_relative './constants'
require_relative './es_query'

def query_commit_status(job, error_id)
  items = {
    'upstream_commit' => job['upstream_commit']
  }
  jobs_list = query_jobs_from_es(items)
  commit_status = parse_jobs_status(jobs_list, error_id)
  return commit_status
end

def query_latest_good_commit(job, error_id)
  items = {
    'suite' => job['suite'],
    'upstream_repo' => job['upstream_repo']
  }
  jobs_list = query_jobs_from_es(items)
  jobs_list = filter_jobs_list(jobs_list, job)
  latest_good_commit = parse_latest_good_commit(jobs_list, error_id)
  return latest_good_commit
end

def query_jobs_from_es(items)
  es = ESQuery.new(ES_HOST, ES_PORT)
  result = es.multi_field_query items
  jobs_list = result['hits']['hits']
  jobs_list.map! { |job| job['_source'] }
  return jobs_list
end

def filter_jobs_list(jobs_list, bad_job)
  jobs_list.delete_if do |item|
    item['id'] == bad_job['id'] ||
      (!item.key? 'commit_date') ||
      item['commit_date'] > bad_job['commit_date']
  end
end

def parse_latest_good_commit(jobs_list, error_id)
  return nil if jobs_list.empty?

  commit_hash = {}
  jobs_list.each do |job|
    commit_id = job['upstream_commit']
    commit_hash[commit_id] = [] unless commit_hash.key? commit_id
    commit_hash[commit_id] << job
  end

  commit_list = commit_hash.to_a
  commit_list.sort_by! { |item| item[1][0]['commit_date'] }.reverse!

  commit_list.each do |item|
    upstream_commit = item[0]
    commit_jobs_list = item[1]
    commit_status = parse_jobs_status(commit_jobs_list, error_id)
    return upstream_commit if commit_status
  end
  return nil
end

def parse_jobs_status(jobs_list, error_id)
  status_list = []
  jobs_list.each do |job|
    next unless job.key? 'stats'

    status_list << (job['stats'].key? error_id)
  end
  return nil if status_list.empty?

  return status_list.none?
end
