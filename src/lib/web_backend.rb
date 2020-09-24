# frozen_string_literal: true

require 'json'
require 'yaml'
require 'set'

CCI_SRC = ENV['CCI_SRC'] || '/c/compass-ci'

require "#{CCI_SRC}/lib/compare.rb"
require "#{CCI_SRC}/lib/constants.rb"
require "#{CCI_SRC}/lib/es_query.rb"
require "#{CCI_SRC}/lib/matrix2.rb"

UPSTREAM_REPOS_PATH = ENV['UPSTREAM_REPOS_PATH'] || '/c/upstream-repos'

FIELDS = %w[
  upstream_repo
  upstream_branch
  upstream_commit
  os
  os_version
  os_arch
  start_time
  suite
  category
  testbox
  job_state
  id
  error_ids
].freeze
NOT_SHOW_FIELDS = %w[result_root].freeze
ALL_FIELDS = FIELDS + NOT_SHOW_FIELDS
NOT_NEED_EXIST_FIELDS = %w[error_ids upstream_branch upstream_repo upstream_commit].freeze
PREFIX_SEARCH_FIELDS = ['tbox_group'].freeze
ES_CLIENT = Elasticsearch::Client.new(url: "http://#{ES_HOST}:#{ES_PORT}")
COMPARE_RECORDS_NUMBER = 50

def es_query(query)
  ES_CLIENT.search index: 'jobs*', body: query
end

def es_count(query)
  ES_CLIENT.count(index: 'jobs*', body: query)['count']
end

# "vm-hi1620-2p8g-212" remove "-212"
# "vm-hi1620-2p8g-zzz" remove "-zzz"
# "vm-git-bisect" don't remove "-bisect"
def filter_tbox_group(es_result)
  result = Set.new
  es_result.each do |r|
    if r =~ /(^.+--.+$)|(^vm-.*-\d\w*-([a-zA-Z]+)|(\d+)$)/
      index = r.index('--') || r.rindex('-')
      r = r[0, index]
    end
    result.add r
  end
  result.to_a
end

def all_suite
  query = {
    aggs: {
      all_suite: {
        terms: { field: 'suite', size: 1000 }
      }
    },
    size: 0
  }
  es_result = es_query(query)['aggregations']['all_suite']['buckets']
  es_result.sort_by! { |h| h['doc_count'] }
  es_result.reverse!.map! { |x|	x['key'] }

  es_result
end

def all_tbox_group
  query = {
    aggs: {
      all_tbox_group: {
        terms: { field: 'tbox_group', size: 1000 }
      }
    },
    size: 0
  }
  es_result = es_query(query)['aggregations']['all_tbox_group']['buckets']
  es_result.sort_by! { |h| h['doc_count'] }
  es_result.reverse!.map! { |x|	x['key'] }

  filter_tbox_group(es_result)
end

def compare_candidates_body
  body = {
    query_conditions: {
      suite: all_suite,
      OS: [
        { os: 'openeuler', os_version: ['1.0', '20.03'] },
        { os: 'centos', os_version: ['7.6', '7.8', '8.1', 'sid'] },
        { os: 'debian', os_version: %w[10 sid] },
        { os: 'archlinux', os_version: ['5.5.0-1'] }
      ],
      os_arch: %w[aarch64 x86_64],
      tbox_group: all_tbox_group
    },
    dimension: %w[os os_version os_arch suite tbox_group]
  }
  JSON.dump body
end

def compare_candidates
  begin
    body = compare_candidates_body
  rescue StandardError => e
    warn e.message
    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), 'get compare candidates error']
  end
  [200, headers.merge('Access-Control-Allow-Origin' => '*'), body]
end

def get_dimension_conditions(params)
  dimension = params.key?(:dimension) ? [params.delete(:dimension)] : []
  conditions = {}
  FIELDS.each do |f|
    v = params[f]
    next if !v || v.empty?

    conditions[f] = v
  end
  return dimension, conditions
end

def get_es_prefix(params)
  prefix = {}
  PREFIX_SEARCH_FIELDS.each do |f|
    v = params[f]
    prefix[f] = v if v
  end
  prefix
end

def get_es_must(params)
  must = []
  prefix = get_es_prefix(params)
  must << { prefix: prefix } unless prefix.empty?
  must << { terms: { job_state: %w[finished failed] } }
  must
end

def get_groups_matrices(conditions, dimension, must, size, from)
  must += build_mutli_field_subquery_body(conditions)
  count_query = { query: { bool: { must: must } } }
  total = es_count(count_query)
  return {} if total < 1

  query = {
    query: {
      bool: {
        must: must
      }
    },
    size: size,
    from: from,
    sort: [{
      start_time: { order: 'desc' }
    }]
  }

  result = es_query(query)
  matrices = combine_group_query_data(result, dimension)
  while matrices.empty?
    from += size
    break if from > total

    query[:from] = from
    result = es_query(query)
    matrices = combine_group_query_data(result, dimension)
  end
  matrices
end

def get_compare_body(params)
  dimension, conditions = get_dimension_conditions(params)
  must = get_es_must(params)
  groups_matrices = get_groups_matrices(conditions, dimension, must, COMPARE_RECORDS_NUMBER, 0)
  if !groups_matrices || groups_matrices.empty?
    body = 'No Data.'
  else
    body = compare_group_matrices(groups_matrices, { no_print: true })
    body = 'No Difference.' if !body || body.empty?
  end
  return body
end

def compare(params)
  begin
    body = get_compare_body(params)
  rescue StandardError => e
    warn e.message
    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), 'compare error']
  end
  [200, headers.merge('Access-Control-Allow-Origin' => '*'), body]
end
