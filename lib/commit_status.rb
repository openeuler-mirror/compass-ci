# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require_relative './constants'
require_relative './es_query'
require_relative './params_group'

def query_commit_status(job, error_id)
  items = {
    'upstream_commit' => job['upstream_commit']
  }
  jobs_list = query_jobs_from_es(items)
  commit_status = parse_jobs_status(jobs_list, error_id)
  return commit_status
end

def query_jobs_from_es(items)
  es = ESQuery.new(ES_HOST, ES_PORT)
  result = es.multi_field_query items
  jobs = result['hits']['hits']
  jobs_list = extract_jobs_list(jobs)
  return jobs_list
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
