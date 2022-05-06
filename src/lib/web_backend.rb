# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'json'
require 'yaml'
require 'set'
require 'time'

CCI_SRC ||= ENV['CCI_SRC'] || '/c/compass-ci'

require "#{CCI_SRC}/lib/my_data.rb"
require "#{CCI_SRC}/lib/compare.rb"
require "#{CCI_SRC}/lib/constants.rb"
require "#{CCI_SRC}/lib/es_query.rb"
require "#{CCI_SRC}/lib/matrix2.rb"
require "#{CCI_SRC}/lib/params_group.rb"
require "#{CCI_SRC}/lib/compare_data_format.rb"
require_relative './job_error.rb'
require_relative './constants.rb'
require_relative './api_input_check.rb'
require_relative '../../lib/json_logger.rb'

UPSTREAM_REPOS_PATH = ENV['UPSTREAM_REPOS_PATH'] || '/c/upstream-repos'

FIELDS = %w[
  upstream_repo
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
NOT_NEED_EXIST_FIELDS = %w[error_ids upstream_repo].freeze
PREFIX_SEARCH_FIELDS = ['tbox_group'].freeze
ES_CLIENT = Elasticsearch::Client.new(hosts: ES_HOSTS)
LOGGING_ES_CLIENT = Elasticsearch::Client.new(hosts: LOGGING_ES_HOSTS)
ES_QUERY = ESQuery.new(ES_HOSTS)
COMPARE_RECORDS_NUMBER = 100
FIVE_DAYS_SECOND = 3600 * 24 * 5

def es_query(query)
  ES_CLIENT.search index: 'jobs*', body: query
end

def es_count(query)
  ES_CLIENT.count(index: 'jobs*', body: query)['count']
end

def page_es_query(must, size, from)
  query = { query: { bool: { must: must } },
            size: size,
            from: from }
  return es_query(query)['hits']['hits']
end

# delete $user after '--' or '.' or '~'
def filter_tbox_group(es_result)
  result = Set.new
  es_result.each do |r|
    r = r.gsub(/(--|\.|~).*$/, '')
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
  filter_es_result(es_result)
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
  es_result = filter_es_result(es_result)

  filter_tbox_group(es_result)
end

def filter_es_result(es_result)
  result_second = []
  es_result.each { |e| result_second << e if e['doc_count'] > 1 }
  result_second.sort_by! { |h| h['doc_count'] }
  result_second.reverse!.map! { |x| x['key'] }
  return result_second
end

def compare_candidates_body
  body = {
    query_conditions: {
      suite: all_suite,
      OS: [
        { os: 'archlinux', os_version: ['5.5.0-1'] },
        { os: 'centos', os_version: ['7.6', '7.8', '8.1'] },
        { os: 'debian', os_version: %w[10 sid] },
        { os: 'openeuler', os_version: ['1.0', '20.03'] }
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
    log_error({
                'message' => e.message,
                'error_message' => 'compare_candidates error'
              })
    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), 'get compare candidates error']
  end
  [200, headers.merge('Access-Control-Allow-Origin' => '*'), body]
end

def get_dimension_conditions(params)
  dimension = params.key?(:dimension) ? [params.delete(:dimension)] : []
  dimension = params.key?(:GROUP_BY) ? [params.delete(:GROUP_BY)] : [] if dimension.empty?

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

def get_dimension_list(dimension)
  query = { size: 0, aggs: { dims: { terms: { size: 10000, field: dimension[0] } } } }
  buckets = es_query(query)['aggregations']['dims']['buckets']
  dimension_list = []
  buckets.each { |dims_agg| dimension_list << dims_agg['key'] }
  return dimension_list
end

def query_dimension(dim_field, dim_value, must, size, from)
  must_dim = Array.new(must)
  must_dim << { term: { dim_field => dim_value } }
  query = {
    query: {
      bool: {
        must: must_dim
      }
    },
    size: size,
    from: from,
    sort: [{
      start_time: { order: 'desc' }
    }]
  }
  es_query(query)['hits']['hits']
end

def get_dimension_job_list(dimension, must, size, from)
  dimension_list = get_dimension_list(dimension)
  job_list = []
  dimension_list.each do |dim|
    job_list += query_dimension(dimension[0], dim, must, size, from)
  end
  job_list
end

def do_get_groups_matrices(must, dimension, total, size, from)
  job_list = get_dimension_job_list(dimension, must, size, from)

  matrices, suites_hash, latest_jobs_hash = Matrix.combine_group_query_data(job_list, dimension)
  while matrices.empty?
    from += size
    break if from > total

    job_list = get_dimension_job_list(dimension, must, size, from)
    matrices, suites_hash, latest_jobs_hash = Matrix.combine_group_query_data(job_list, dimension)
  end
  [matrices, suites_hash, latest_jobs_hash]
end

def get_groups_matrices(conditions, dimension, must, size, from)
  must += build_multi_field_subquery_body(conditions)
  count_query = { query: { bool: { must: must } } }
  total = es_count(count_query)
  return {} if total < 1

  do_get_groups_matrices(must, dimension, total, size, from)
end

def get_compare_body(params)
  dimension, conditions = get_dimension_conditions(params)
  must = get_es_must(params)
  groups_matrices, suites_hash, latest_jobs_hash =
    get_groups_matrices(conditions, dimension, must, COMPARE_RECORDS_NUMBER, 0)
  if !groups_matrices || groups_matrices.empty?
    body = 'No Data.'
  else
    body = compare_group_matrices(groups_matrices, suites_hash, latest_jobs_hash, { no_print: true })
    body = 'No Difference.' if !body || body.empty?
  end
  return body
end

def compare(params)
  begin
    body = get_compare_body(params)
  rescue StandardError => e
    log_error({
                'message' => e.message,
                'error_message' => "compare error, input: #{params}"
              })
    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), 'compare error']
  end
  [200, headers.merge('Access-Control-Allow-Origin' => '*'), body]
end

def space_to_nil(str)
  return unless str

  str&.strip!
  str.empty? ? nil : str
end

def get_positive_number(num, default_num)
  num = num.to_i
  return default_num unless num.positive?

  return num
rescue StandardError
  return default_num
end

def wrong_size?(size, from)
  return true if from.negative? || size.negative?

  return true if from > 1000000 || size > 1000000

  return true if size + from > 1000000
end

def es_search(must, size, from)
  count_query = { query: { bool: { must: must } } }
  total = es_count(count_query)
  unless size
    size = total
    from = 0
  end
  query = {
    query: { bool: { must: must } },
    size: size,
    from: from,
    sort: [{
      start_time: { order: 'desc' },
      id: { order: 'desc' }
    }]
  }
  return {}, total if wrong_size?(size, from)

  return es_query(query)['hits']['hits'], total
end

def get_jobs_result(result)
  jobs = []
  result.each do |r|
    job = {}
    ALL_FIELDS.each do |f|
      job[f] = r['_source'][f]
    end
    jobs << job
  end
  jobs
end

def get_job_query_range(condition_fields)
  range = { start_time: {} }
  start_date = condition_fields[:start_date]
  end_date = condition_fields[:end_date]

  if start_date
    range[:start_time][:gte] = "#{start_date}T00:00:00+0800" if start_date
    condition_fields.delete('start_date')
  end

  if end_date
    range[:start_time][:lte] = "#{end_date}T23:59:59+0800" if end_date
    condition_fields.delete('end_date')
  end

  unless start_date || end_date
    return nil
  end

  { range: range }
end

MAX_JOBS_NUM = 1000000
def search_job(condition_fields, page_size, page_num)
  must = []
  range = get_job_query_range(condition_fields)
  if range
    must << range if range[:range][:start_time]
  end

  condition_fields.keys.each do |field|
    value = space_to_nil(condition_fields[field])
    next unless value

    must << if field.to_s == 'upstream_repo'
              { regexp: { field => ".*#{value}.*" } }
            else
              { term: { field => value } }
            end
  end

  result, total = es_search(must, page_size, page_num * page_size)
  total = MAX_JOBS_NUM if total > MAX_JOBS_NUM
  return get_jobs_result(result), total
end

def get_banner(git_repo, branches)
  {
    repo: git_repo,
    git_url: get_repo(git_repo)[:git_url],
    upstream_branch: branches
  }
end

def get_optimize_jobs_branches(jobs)
  branch_set = Set.new
  jobs.size.times do |i|
    branch = jobs[i]['upstream_branch'].to_s
    if branch.empty?
      jobs[i]['upstream_branch'] = 'master'
      branch_set.add 'master'
    else
      jobs[i]['upstream_branch'] = branch
      branch_set.add branch
    end
  end
  return jobs, branch_set.to_a
end

def get_jobs_body(params)
  page_size = get_positive_number(params.delete(:page_size), 20)
  page_num = get_positive_number(params.delete(:page_num), 1) - 1
  jobs, total = search_job(params, page_size, page_num)
  jobs, branches = get_optimize_jobs_branches(jobs)
  {
    total: total,
    filter: params,
    banner: get_banner(params[:upstream_repo], branches),
    jobs: jobs,
    fields: FIELDS
  }.to_json
end

def get_jobs(params)
  begin
    body = get_jobs_body(params)
  rescue StandardError => e
    log_error({
                'message' => e.message,
                'error_message' => "get_jobs error, input: #{params}"
              })
    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), 'get jobs error']
  end
  [200, headers.merge('Access-Control-Allow-Origin' => '*'), body]
end

def get_repo_url(urls)
  return unless urls.is_a?(Array)

  urls.each do |url|
    return url if url[0, 4] == 'http'
  end

  urls[0]
end

def get_repo(git_repo)
  repo = nil
  if git_repo
    must = [{ regexp: { git_repo: ".*#{git_repo}.*" } }]
    repo = query_repos(must, from: 0, size: 1)[0]
  end
  repo || {}
end

def query_repos(must, from: 0, size: 1)
  query = {
    query: { bool: { must: must } },
    size: size,
    from: from,
    sort: [{
      git_repo: { order: 'asc' }
    }]
  }
  result = ES_CLIENT.search index: 'repo', body: query
  repos = []
  result['hits']['hits'].each do |r|
    r = r['_source']

    repos << {
      git_url: get_repo_url(r['url']),
      git_repo: r['git_repo']
    }
  end
  repos
end

def search_repos(git_repo, page_size, page_num)
  size = page_size
  from = size * page_num
  must = git_repo ? [{ regexp: { git_repo: ".*#{git_repo}.*" } }] : []

  # What does this regular expression want:
  # 1. a three-segment structure "xxx/xxx/xxx"
  # 2. there can be '-' or '_' in every segment, but can't be at first or last of the segment.
  # 3. the first segment can have lowercase of letters or numbers in it.
  # 4. the other two segments can have letters(lowercase or uppercase) or numbers in it.
  must << { regexp: { git_repo: "[a-z0-9]([a-z0-9\-_]*[a-z0-9])*(/[a-zA-Z0-9][a-zA-Z0-9\-_]*[a-zA-Z0-9]){2}" } }

  count_query = { query: { bool: { must: must } } }
  total = ES_CLIENT.count(index: 'repo', body: count_query)['count']
  return [], total if wrong_size?(size, from)

  return query_repos(must, from: from, size: size), total
end

def get_repos_body(params)
  page_size = get_positive_number(params[:page_size], 20)
  page_num = get_positive_number(params[:page_num], 1) - 1
  git_repo = params[:git_repo]

  repos, total = search_repos(git_repo, page_size, page_num)

  {
    total: total,
    repos: repos
  }.to_json
end

def get_repos(params)
  begin
   body = get_repos_body(params)
  rescue StandardError => e
    log_error({
                'message' => e.message,
                'error_message' => "get_repos error, input: #{params}"
              })
    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), 'get repos error']
 end
  [200, headers.merge('Access-Control-Allow-Origin' => '*'), body]
end

def query_filed(params)
  begin
   body = get_job_field(params)
  rescue StandardError => e
    log_error({
                'message' => e.message,
                'error_message' => "query_filed error, input: #{params}"
              })
    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), 'query_filed error']
 end
  [200, headers.merge('Access-Control-Allow-Origin' => '*'), body]
end

def get_job_field(params)
  request_body = JSON.parse(params)
  items = request_body['filter']
  count_keywords = [request_body['field']]
  query_result = ES_QUERY.query_fields(count_keywords, items)
  return [].to_json unless query_result

  query_result.keys.to_json
end

def performance_result(data)
  begin
    request_body = JSON.parse(data)
    incorrect_input = check_performance_result(request_body)
    return [406, headers.merge('Access-Control-Allow-Origin' => '*'), incorrect_input] if incorrect_input

    body = result_body(request_body)
  rescue StandardError => e
    log_error({
                'message' => e.message,
                'error_message' => "performance_result error, input: #{params}"
              })
    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), 'get performance result error']
  end
  [200, headers.merge('Access-Control-Allow-Origin' => '*'), body]
end

def result_body(request_body)
  transposed = true
  if request_body['x_params'].include?('metric')
    request_body['x_params'] = ['suite']
    transposed = false
  end

  result = []
  groups_matrices, series, group_testbox = create_groups_matrices(request_body)
  return result.to_json if groups_matrices.empty?

  series = combine_compare_dims(request_body['series']) unless request_body['max_series_num'] && request_body['max_series_num'] > 0

  groups_matrices.each do |group, group_matrices|
    compare_results = compare_metrics_values(group_matrices, series)
    formatter = FormatEchartData.new(compare_results, request_body, group, series, group_testbox)
    echart_data = formatter.format_echart_data(transposed)
    result += echart_data
  end
  result.to_json
end

def search_testboxes
  query = { size: 0, aggs: { testboxes: { terms: { size: 10000, field: 'testbox' } } } }
  buckets = es_query(query)['aggregations']['testboxes']['buckets']
  testboxes = []
  buckets.each { |tbox_agg| testboxes << tbox_agg['key'] }
  return testboxes, testboxes.length
end

def testboxes_body
  testboxes, total = search_testboxes
  {
    total: total,
    testboxes: testboxes
  }.to_json
end

def query_testboxes
  begin
    body = testboxes_body
  rescue StandardError => e
    log_error({
                'message' => e.message,
                'error_message' => 'query_testboxes error'
              })
    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), 'get testboxes error']
  end
  [200, headers.merge('Access-Control-Allow-Origin' => '*'), body]
end

def get_tbox_state_body(params)
  query = {
    "query": {
      "match": {
        "_id": params[:testbox]
      }
    }
  }
  body = ES_CLIENT.search(index: 'testbox', body: query)['hits']['hits'][0]['_source']

  {
    testbox: params[:testbox],
    states: body
  }.to_json
end

def get_tbox_state(params)
  begin
    body = get_tbox_state_body(params)
  rescue StandardError => e
    log_error({
                'message' => e.message,
                'error_message' => "get_tbox_state error, input: #{params}"
              })
    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), 'get testbox state error']
  end
  [200, headers.merge('Access-Control-Allow-Origin' => '*'), body]
end

def get_echart(statistics)
  echart = {
    'title' => 'new refs statistics',
    'unit' => 'times',
    'x_name' => 'date',
    'source' => [['x_params'], ['new_ref_times']]
  }
  dev = 1
  # The day will be 2021-01-01
  day = Date.new(2021, 1, 1)
  today = Date.today
  while day <= today
    day_s = day.to_s
    echart['source'][0][dev] = day_s
    echart['source'][1][dev] = statistics[day_s] || 0
    day += 1
    dev += 1
  end
  echart
end

def query_repo_statistics(params)
  query = { "query": { "match": { "_id": params[:git_repo] } } }
  result = ES_CLIENT.search(index: 'repo', body: query)['hits']
  statistics = result['total'].positive? ? result['hits'][0]['_source']['new_refs_count'] : {}
  get_echart(statistics)
end

def new_refs_statistics(params)
  begin
    body = query_repo_statistics(params)
  rescue StandardError => e
    log_error({
                'message' => e.message,
                'error_message' => "new_refs_statistics error, input: #{params}"
              })
    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), 'new refs statistics error']
  end
  [200, headers.merge('Access-Control-Allow-Origin' => '*'), body]
end

def single_count(stats)
  fail_count = 0
  pass_count = 0
  single_nr_fail = 0
  single_nr_pass = 0
  stats.each do |stat, value|
    fail_count += 1 if stat.match(/\.fail$/i)
    pass_count += 1 if stat.match(/\.pass$/i)
    single_nr_fail = value if stat.match(/\.nr_fail$/i)
    single_nr_pass = value if stat.match(/\.nr_pass$/i)
  end
  fail_count = single_nr_fail.zero? ? fail_count : single_nr_fail
  pass_count = single_nr_pass.zero? ? pass_count : single_nr_pass
  [fail_count, pass_count, fail_count + pass_count]
end

def count_stats(job_list, dimension, dim)
  nr_stats = { dimension => dim, 'nr_fail' => 0, 'nr_pass' => 0, 'nr_all' => 0 }
  job_list.each do |job|
    next unless job['_source']['stats']

    fail_count, pass_count, all_count = single_count(job['_source']['stats'])
    nr_stats['nr_fail'] += fail_count
    nr_stats['nr_pass'] += pass_count
    nr_stats['nr_all'] += all_count
  end
  nr_stats
end

def get_jobs_stats_count(dimension, must, size, from)
  dimension_list = get_dimension_list(dimension)
  stats_count = []
  dimension_list.each do |dim|
    job_list = query_dimension(dimension[0], dim, must, size, from)
    stats_count << count_stats(job_list, dimension[0], dim)
  end
  stats_count
end

def get_stats_by_dimension(conditions, dimension, must, size, from)
  must += build_multi_field_subquery_body(conditions)
  count_query = { query: { bool: { must: must } } }
  total = es_count(count_query)
  return {} if total < 1

  get_jobs_stats_count(dimension, must, size, from)
end

def get_jobs_stats(params)
  dimension, conditions = get_dimension_conditions(params)
  must = get_es_must(params)
  objects = get_stats_by_dimension(conditions, dimension, must, 1000, 0)
  {
    filter: params,
    attributes: [dimension[0], 'nr_all', 'nr_pass', 'nr_fail'],
    objects: objects
  }.to_json
end

def group_jobs_stats(params)
  begin
    body = get_jobs_stats(params)
  rescue StandardError => e
    log_error({
                'message' => e.message,
                'error_message' => "group_jobs_stats error, input: #{params}"
              })
    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), 'group jobs table error']
  end
  [200, headers.merge('Access-Control-Allow-Origin' => '*'), body]
end

# -------------------------------------------------------------------------------------------
# job error table like:
#   job_id           error_id           error_message           result_root
#   -------------------------------------------------------------------------------------
#   crystal.630608   "stderr.xxx"       "messag:xxxx"           $result_root
#   ...
# -------------------------------------------------------------------------------------------

def get_job_error(params)
  begin
    body = job_error_body(params)
  rescue StandardError => e
    log_error({
                'message' => e.message,
                'error_message' => "get_job_error error, input: #{params}"
              })
    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), 'get error table error']
  end

  [200, headers.merge('Access-Control-Allow-Origin' => '*'), body]
end

def job_error_body(params)
  error_objects = get_error_objects(params)
  {
    filter: params,
    attributes: %w[job_id error_message result_root stderr],
    objects: error_objects
  }.to_json
end

def get_error_objects(filter_items)
  error_objs = []

  job_list = get_job_list(filter_items)
  job_list.each do |job|
    error_obj = get_error_from_job(job)
    error_objs << error_obj unless error_obj.empty?
  end

  error_objs
end

def get_job_list(items)
  es = ESQuery.new
  query_results = es.multi_field_query(items)

  extract_jobs_list(query_results['hits']['hits'])
end

# get all error_id from one job
def get_error_from_job(job)
  job_error_obj = {}
  job['stats'].each do |metric, value|
    next unless metric.end_with?('.message')

    error_id = metric.sub('.message', '.fail')
    job_error_obj['job_id'] = job['id']
    job_error_obj['error_message'] = value
    job_error_obj['result_root'] = job['result_root']
    job_error_obj['stderr'] = job['result_root'] + '/stderr'
  end

  job_error_obj
end

def msg_per_hour
  query = {
    "query": {
      "bool": {
        "filter": [
          { "exists": { "field": 'msg' } },
          { "range": { "time": { "gt": 'now-1h' } } }
        ]
      }
    }
  }
  LOGGING_ES_CLIENT.count(index: 'git-mirror', body: query)['count']
end

def worker_threads_alive
  query = {
    query: {
      bool: {
        filter: [
          { exists: { field: 'state' } },
          { range: { time: { gt: 'now-5m' } } }
        ]
      }
    },
    size: 1,
    sort: [{
      time: { order: 'desc' }
    }]
  }
  result = LOGGING_ES_CLIENT.search(index: 'git-mirror', body: query)['hits']
  num = result['total']['value']
  return ['OK', 10] if num.zero?

  return [result['hits'][0]['_source']['level'], result['hits'][0]['_source']['alive_num']]
end

def git_mirror_state
  msg_count = msg_per_hour
  state, alive_num = worker_threads_alive
  state = 'WARN' if state == 'OK' && msg_count.zero?
  [state, alive_num, msg_count].to_json
end

def git_mirror_health
  begin
    body = git_mirror_state
  rescue StandardError => e
    log_error({
                'message' => e.message,
                'error_message' => 'git_mirror_health error'
              })
    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), 'git mirror health error']
  end
  [200, headers.merge('Access-Control-Allow-Origin' => '*'), body]
end

def get_active_testbox
  begin
    my_data = MyData.new
    active_vm = my_data.get_testbox_aggs(type: 'vm')
    active_dc = my_data.get_testbox_aggs(type: 'dc')
    active_physical = my_data.get_testbox_aggs

    result = {
      'vm' => active_vm['aggregations']['queue']['buckets'],
      'dc' => active_dc['aggregations']['queue']['buckets'],
      'physical' => active_physical['aggregations']['queue']['buckets']
    }.to_json
  rescue StandardError => e
    log_error({
                'message' => e.message,
                'error_message' => 'get_active_testbox error'
              })

    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), 'get active testbox error']
  end

  [200, headers.merge('Access-Control-Allow-Origin' => '*'), result]
end

# ---------------------------------------------------------------------------------------------------------
# active-stderr, we will use the response create table like:
#  total | first date | suite | job_owner        | relevant-links(link) | error_message
#  16    | 2021-6-15  | iperf | compass-ci-robot | job_ids              | stderr.Dload_Upload_Total_Spent_Left_Speed
#  15    | 2021-6-15  | iperf | compass-ci-robot | job_ids              | stderr.Can_not_find_perf_command
#  ...
# ---------------------------------------------------------------------------------------------------------
def active_stderr
  begin
    body = active_stderr_body
  rescue StandardError => e
    log_error({
                'message' => e.message,
                'error_message' => 'active_stderr error'
              })
    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), 'get active-stderr error']
  end
  [200, headers.merge('Access-Control-Allow-Origin' => '*'), body]
end

def active_stderr_body
  now = Time.now # like: 2021-06-23 17:21:55 +0800
  query_result = es_query(five_days_query(now))['hits']['hits']
  job_list = extract_jobs_list(query_result)

  # get today jobs error
  job_error = JobError.new(job_list, now)
  jobs_errors = job_error.active_error

  {
    'total' => jobs_errors.size,
    'cols' => %w[count first_date suite job_owner relevant_links error_message],
    'data' => jobs_errors
  }.to_json
end

def five_days_query(now)
  d5 = now - FIVE_DAYS_SECOND

  { query: {
    bool: {
      must: [{ range: {
        'start_time' => { gte: d5.strftime('%Y-%m-%dT%H:%M:%S+0800'), lte: now.strftime('%Y-%m-%dT%H:%M:%S+0800') }
      } }],
      must_not: { bool: { should: [{ term: { 'suite' => 'rpmbuild' } }, { term: { 'suite' => 'build-pkg' } }] } }
    }
  },
    size: 10000,
    sort: [{ 'start_time' => { order: 'desc' } }] }
end

def es_query_boot_job(from, size, must)
  job_list = []
  es_results = page_es_query(must, size, from)
  es_results.each do |es_result|
    next unless es_result['_source']['boot_elapsed_time']

    job_list << es_result['_source']
  end
  return job_list
end

def get_one_day_must(now)
  d1 = now - ONE_DAY_SECOND

  [{ range: {
    'start_time' => { gte: d1.strftime('%Y-%m-%dT%H:%M:%S+0800'), lte: now.strftime('%Y-%m-%dT%H:%M:%S+0800') }
  } }]
end

def response_boot_time_by_pages(pages, interface, must, response, from, size)
  pages.times do |_i|
    job_list = es_query_boot_job(from, size, must)
    if interface == 'boot_time'
      response_boot_time(job_list, response)
    else
      response = { 'hw' => [], 'vm' => [], 'dc' => [] }
      response_top_boot_time(job_list, response)
    end
    from += size
  end
  response
end

def get_job_boot_time(interface)
  size = 10000
  from = 0
  must = get_one_day_must(Time.now)
  response = boot_time_response
  pages = es_count({ query: { bool: { must: must } } }) / size + 1
  response = response_boot_time_by_pages(pages, interface, must, response, from, size)
  return response.to_json
end

def boot_time_response
  response = { 'dc' => { 'threshold' => 60, 'x_params' => [], 'boot_time' => [] },
               'vm' => { 'threshold' => 180, 'x_params' => [], 'boot_time' => [] },
               'hw' => { 'threshold' => 600, 'x_params' => [], 'boot_time' => [] } }
end

def response_boot_time(job_list, response)
  job_list.each do |job|
    testbox_type = job['testbox'][0, 2]
    testbox_type = 'hw' unless testbox_type.match?(/dc|vm/)
    response[testbox_type]['x_params'] << job['id']
    response[testbox_type]['boot_time'] << job['boot_elapsed_time']
  end
  return response.to_json
end

def job_boot_time
  begin
    body = get_job_boot_time('boot_time')
  rescue StandardError => e
    log_error({
                'message' => e.message,
                'error_message' => 'job_boot_time error'
              })
    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), 'get job_boot_time error']
  end
  [200, headers.merge('Access-Control-Allow-Origin' => '*'), body]
end

def response_top_boot_time(job_list, response)
  threshold = { 'hw' => 600, 'vm' => 180, 'dc' => 60 }
  job_list.each do |job|
    testbox_type = job['testbox'][0, 2]
    testbox_type = 'hw' unless testbox_type.match?(/dc|vm/)
    boot_time = job['boot_elapsed_time']
    next if boot_time <= threshold[testbox_type]

    response[testbox_type] << { 'job_id' => job['id'], 'boot_time' => boot_time, 'result_root' => job['result_root'] }
  end
  response.each_key do |k|
    response[k].sort! { |a, b| b['boot_time'] <=> a['boot_time'] }
    response[k] = response[k][0..19] if response[k].length > 20
  end
  response
end

def top_boot_time
  begin
    body = get_job_boot_time('top_boot_time')
  rescue StandardError => e
    log_error({
                'message' => e.message,
                'error_message' => 'top_boot_time error'
              })
    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), 'get top_boot_time error']
  end
  [200, headers.merge('Access-Control-Allow-Origin' => '*'), body]
end

def get_srpm_info(params)
  begin
    all = {}
    info = []
    body = get_srpm_software_body(params)
    total = JSON.parse(body)['total']

    all.store('total', total)
    JSON.parse(body)['compats']['hits']['hits'].each do |source|
      info << source['_source']
    end
    all.store('info', info)
  rescue StandardError => e
    log_error({
                'message' => e.message,
                'error_message' => "get_srpm_software_body error, input: #{params}"
              })
    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), 'get srpm software info error']
  end
  [200, headers.merge('Access-Control-Allow-Origin' => '*'), all.to_json]
end

def get_compat_software_body(params)
  page_size = get_positive_number(params.delete(:page_size), 10)
  page_num = (get_positive_number(params.delete(:page_num), 1) - 1) * page_size

  total_query = {
    query: {
      bool: {
        must: build_multi_field_body(params)
      }
    }
  }

  compats_query = {
    query: {
      bool: {
        must: build_multi_field_body(params)
      }
    },
    size: page_size,
    from: page_num
  }

  total = ES_CLIENT.count(index: 'compat-software-info', body: total_query)['count']
  compats = ES_CLIENT.search index: 'compat-software-info', body: compats_query
  {
    total: total,
    filter: params,
    compats: compats
  }.to_json
end

def get_compat_software(params)
  begin
    all = {}
    info = []
    body = get_compat_software_body(params)
    total = JSON.parse(body)['total']

    all.store('total', total)
    JSON.parse(body)['compats']['hits']['hits'].each do |source|
      info << source['_source']
    end
    all.store('info', info)
  rescue StandardError => e
    log_error({
                'message' => e.message,
                'error_message' => "get_compat_software_body error, input: #{params}"
              })
    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), 'get compat software info error']
  end
  [200, headers.merge('Access-Control-Allow-Origin' => '*'), all.to_json]
end

def get_srpm_software_body(params)
  page_size = get_positive_number(params.delete(:page_size), 10)
  page_num = (get_positive_number(params.delete(:page_num), 1) - 1) * page_size

  total_query = {
    query: {
      bool: {
        filter: [
          exists: {
            field: 'softwareName'
          }
        ],
        must: build_multi_field_body(params)
      }
    }
  }

  srpm_query = {
    query: {
      bool: {
        filter: [
          exists: {
            field: 'softwareName'
          }
        ],
        must: build_multi_field_body(params)
      }
    },
    size: page_size,
    from: page_num
  }

  total = ES_CLIENT.count(index: 'srpm-info*', body: total_query)['count']
  compats = ES_CLIENT.search index: 'srpm-info*', body: srpm_query
  {
    total: total,
    filter: params,
    compats: compats
  }.to_json
end

def build_multi_field_body(items)
  query_fields = []
  items.each do |key, value|
    if value.is_a?(Array)
      inner_query = build_multi_field_or_query_body(key, value)
      query_fields.push({ bool: { should: inner_query } })
    else
      if key == 'softwareName' || key == 'keyword'
        query_fields.push({ regexp: { 'softwareName' => ".*#{value}.*" } })
      else
        next if key == 'rnd'

        query_fields.push({ term: { key.to_s => value } })
      end
    end
  end
  query_fields
end

def get_compat_software_info_detail
  begin
    my_data = MyData.new

    data = my_data.query_compat_software
  rescue StandardError => e
    log_error({
                'message' => e.message,
                'error_message' => 'query_compat_software error'
              })
    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), 'query compat software info error']
  end
  [200, headers.merge('Access-Control-Allow-Origin' => '*'), data.to_json]
end

def query_latest_commit_id(params)
  num = params[:group_id].split('-').count
  if params[:group_id].split('-').count == 1
    es = ESQuery.new
    upstream_repo = params[:group_id][0, 1] + '/' + params[:group_id] + '/' + params[:group_id]
    query_result = es.multi_field_query({ 'upstream_repo' => upstream_repo }, desc_keyword: 'start_time')['hits']['hits']
    upstream_commit = query_result[0]['_source']['upstream_commit']
    params[:group_id] = params[:group_id] + '-' + upstream_commit
  end
  params
end

def query_test_matrix_result(params)
  es = ESQuery.new
  params = query_latest_commit_id(params)

  query_result = es.multi_field_query({ 'group_id' => params[:group_id] })
  result_hash = {}
  query_result['hits']['hits'].each do |r|
    item = {}
    key = "#{r['_source']['os']}-#{r['_source']['os_version']}-#{r['_source']['os_arch']}"
    if result_hash.key?(key)
      item = result_hash[key]
    else
      item['os'] = r['_source']['os']
      item['os_version'] = r['_source']['os_version']
      item['os_arch'] = r['_source']['os_arch']
    end

    if r['_source']['suite'] == 'rpmbuild'
      item['build_id'] = r['_id']
      item['build_job_health'] = r['_source']['job_health']
      if (r['_source']['stats'].nil? == false) && r['_source']['stats'].has_key?('rpmbuild.func.message')
        item['func_job_health'] = r['_source']['stats']['rpmbuild.func.message']
      end
    end

    if r['_source']['suite'] == 'install-rpm'
      install_item = get_install_info(r)
      item['install_id'] = install_item['id']
      item['install_job_health'] = install_item['job_health']
    end
    result_hash[key] = item
  end
  result = []
  result_hash.each_value do |v|
    result << v
  end
  result
end

def query_test_matrix(params)
  begin
    result = query_matrix_result(params)
  rescue StandardError => e
    log_error({
                'message' => e.message,
                'error_message' => 'query_result_error'
              })
    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), 'query result error']
  end
  [200, headers.merge('Access-Control-Allow-Origin' => '*'), result.to_json]
end

def query_matrix_result(params)
  es = ESQuery.new
  params = query_latest_commit_id(params)

  query_result = es.multi_field_query({ 'group_id' => params[:group_id] })
  result = []
  query_result['hits']['hits'].each do |r|
    item = get_job_info(r)
    result << item
  end
  result
end

# eg:
# input: ES job query result['hits']['hits']
# output: {"os"=>"openeuler", "os_version"=>"20.03-LTS-SP1", "os_arch"=>"aarch64", "result_root"=>"/result/rpmbuild/2022-03-23/dc-16g/openeuler-20.03-LTS-SP1-aarch64/elrepo-aarch64-e-elrepo-elrepo/crystal.5236306", "id"=>"crystal.5236306", "build_job_health"=>"success", "install_job_health"=>"success"}
def get_job_info(job)
  job_info = {}
  need_keys = %w[os os_version os_arch result_root]
  need_keys.each do |k|
    job_info[k] = job['_source'][k]
  end
  job_info['id'] = job['_id']
  stats = job['_source']['stats']
  return job_info if stats.nil?

  job_info['build_job_health'] = if stats.key?('rpmbuild.start_time.message')
                                   'success'
                                 else
                                   'fail'
                                 end
  job_info['func_job_health'] = 'success' if stats.key?('rpmbuild.func.message')
  job_info['install_job_health'] = 'fail'
  stats.each do |k, _v|
    case k
    when /install-rpm\.(.*)_(?:install|uninstall|)\.(.*)/
      if $2 == 'fail'
        job_info['install_job_health'] = 'fail'
        return job_info
      else
        job_info['install_job_health'] = 'success'
      end

    when /install-rpm\.(.*)_(?:cmd|service)_(.*)\.(.*)/
      if $3 == 'fail'
        job_info['install_job_health'] = 'fail'
        return job_info
      else
        job_info['install_job_health'] = 'success'
      end
    end
  end
  job_info
end

def get_install_info(result)
  install_info = {}
  install_info['id'] = result['_id']
  result = result['_source']['stats']

  result.each do |k, _v|
    case k
    when /install-rpm\.(.*)_(?:install|uninstall|)\.(.*)/
      if $2 == 'fail'
        install_info['job_health'] = 'fail'
        return install_info
      end

    when /install-rpm\.(.*)_(?:cmd|service)_(.*)\.(.*)/
      if $3 == 'fail'
        install_info['job_health'] = 'fail'
        return install_info
      end
    end
  end
  install_info['job_health'] = 'success'
  install_info
end

def query_host_info(params)
  begin
    result = get_host_content(params)
  rescue StandardError => e
    log_error({
                'message' => e.message,
                'error_message' => 'query host info error'
              })
    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), 'query host info error']
  end
  [200, headers.merge('Access-Control-Allow-Origin' => '*'), result.to_json]
end

def get_host_content(params)
  testbox = params['testbox'] || nil
  return 'please give testbox params' unless testbox

  # read host file
  file_path = "/c/lab-#{LAB}/hosts/#{testbox}"
  return "the testbox: #{testbox} doesn't exists" unless File.file?(file_path)

  YAML.load_file(file_path)
end
