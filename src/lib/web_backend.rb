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
COMPARE_RECORDS_NUMBER = 100
FIVE_DAYS_SECOND = 3600 * 24 * 5

def es_query(query)
  ES_CLIENT.search index: 'jobs*', body: query
end

def es_count(query)
  ES_CLIENT.count(index: 'jobs*', body: query)['count']
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
    warn e.message
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
    warn e.message
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
  FIELDS.each do |f|
    next if NOT_NEED_EXIST_FIELDS.include? f

    must << { exists: { field: f } }
  end
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

  range[:start_time][:gte] = "#{start_date} 00:00:00" if start_date
  range[:start_time][:lte] = "#{end_date} 23:59:59" if end_date

  { range: range }
end

MAX_JOBS_NUM = 1000000
def search_job(condition_fields, page_size, page_num)
  must = []
  FIELDS.each do |field|
    value = space_to_nil(condition_fields[field])
    next unless value

    must << if field.to_s == 'upstream_repo'
              { regexp: { field => ".*#{value}.*" } }
            else
              { term: { field => value } }
            end
  end
  range = get_job_query_range(condition_fields)
  must << range if range[:range][:start_time]
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
    warn e.message
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
    warn e.message
    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), 'get repos error']
 end
  [200, headers.merge('Access-Control-Allow-Origin' => '*'), body]
end

def performance_result(data)
  begin
    body = result_body(JSON.parse(data))
  rescue StandardError => e
    warn e.message
    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), 'compare error']
  end
  [200, headers.merge('Access-Control-Allow-Origin' => '*'), body]
end

def result_body(request_body)
  groups_matrices = create_groups_matrices(request_body)
  compare_results, series = compare_metrics_values(groups_matrices)
  formatter = FormatEchartData.new(compare_results, request_body, series)
  formatter.format_echart_data.to_json
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
    warn e.message
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
    warn e.message
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
    warn e.message
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
    attributes: [ dimension[0], 'nr_all', 'nr_pass', 'nr_fail' ],
    objects: objects,
  }.to_json
end

def group_jobs_stats(params)
  begin
    body = get_jobs_stats(params)
  rescue StandardError => e
    warn e.message
    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), 'group jobs table error']
  end
  [200, headers.merge('Access-Control-Allow-Origin' => '*'), body]
end

# -------------------------------------------------------------------------------------------
# job error table like:
#   job_id           error_id           error_message           link to result
#   -------------------------------------------------------------------------------------
#   crystal.630608   "stderr.xxx"       "messag:xxxx"           https://$host:$port/$result_root
#   ...
# -------------------------------------------------------------------------------------------

def get_job_error(params)
  begin
    body = job_error_body(params)
  rescue StandardError => e
    warn e.message
    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), 'get error table error']
  end

  [200, headers.merge('Access-Control-Allow-Origin' => '*'), body]
end

def job_error_body(params)
  error_objects  = get_error_objects(params)
  {
    filter: params,
    attributes: ['job_id', 'error_id', 'error_message', 'link_to_result'],
    objects: error_objects,
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

    result_host = ENV['SRV_HTTP_RESULT_HOST'] || SRV_HTTP_RESULT_HOST
    result_port = ENV['SRV_HTTP_RESULT_PORT'] || SRV_HTTP_RESULT_PORT
    error_id = metric.sub('.message', '.fail')
    job_error_obj['job_id'] = job['id']
    job_error_obj['error_id'] = error_id
    job_error_obj['error_message'] = value
    job_error_obj['link_to_result'] = "http://#{result_host}:#{result_port}#{job['result_root']}"
  end

  job_error_obj
end

def msg_per_hour
  query = {
    "query": {
      "bool": {
        "filter": [
          { "exists": { "field": "msg" } },
          { "range": { "time": { "gt": "now-1h" } } }
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
          { exists: { field: "state" } },
          { range: { time: { gt: "now-5m" } } }
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
  return [ 'OK', 10 ] if num.zero?
  return [ result['hits'][0]['_source']['level'], result['hits'][0]['_source']['alive_num'] ]
end

def git_mirror_state
  msg_count = msg_per_hour
  state, alive_num = worker_threads_alive
  state = 'WARN' if state == 'OK' && msg_count.zero?
  [ state, alive_num, msg_count ].to_json
end

def git_mirror_health
  begin
    body = git_mirror_state
  rescue StandardError => e
    warn e.message
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
    warn e.message

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
    warn e.message
    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), 'get active-stderr error']
  end
  [200, headers.merge('Access-Control-Allow-Origin' => '*'), body]
end

def active_stderr_body
  now = Time.now  # like: 2021-06-23 17:21:55 +0800
  query_result = es_query(five_days_query(now))['hits']['hits']
  job_list = extract_jobs_list(query_result)

  # get today jobs error
  job_error = JobError.new(job_list, now)
  jobs_errors = job_error.active_error

  {
    'total' => jobs_errors.size,
    'cols' => ['count', 'first_date', 'suite', 'job_owner', 'relevant_links', 'error_message'],
    'data' => jobs_errors
  }.to_json
end

def five_days_query(now)
  d5 = now - FIVE_DAYS_SECOND

  {:query => {
      :bool => {
        :must => [{:range => {
          "start_time" => {:gte => d5.strftime("%Y-%m-%d %H:%M:%S"), :lte => now.strftime("%Y-%m-%d %H:%M:%S")}
        }}]
      }
    },
    :size => 10000,
    :sort => [{"start_time" => {:order=>"desc"}}]
  }
end

def es_query_boot_job
  query = {
    query: {
      bool: {
        must: { term: { 'job_stage' => 'boot' } }
      }
    }, size: 10000
  }
  es_results = es_query(query)['hits']['hits']
  job_list = []
  es_results.each do |es_result|
    next unless es_result['_source']['boot_time']

    job_list << es_result['_source']
  end
  return job_list
end

def get_job_boot_time
  response = { 'dc' => { 'threshold' => 60 , 'x_params' => [], 'boot_time' => [] },
               'vm' => { 'threshold' => 180, 'x_params' => [], 'boot_time' => [] },
               'hw' => { 'threshold' => 600, 'x_params' => [], 'boot_time' => [] }
             }
  job_list = es_query_boot_job
  job_list.each do |job|
    testbox_type = job['testbox'][0, 2]
    testbox_type = 'hw' unless testbox_type.match?(/dc|vm/)
    response[testbox_type]['x_params'] << job['id']
    boot_time = (Time.now - Time.parse(job['boot_time'])).to_i
    response[testbox_type]['boot_time'] << boot_time
  end
  return response.to_json
end

def job_boot_time
  begin
    body = get_job_boot_time
  rescue StandardError => e
    warn e.message
    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), 'get job_boot_time error']
  end
  [200, headers.merge('Access-Control-Allow-Origin' => '*'), body]
end

def get_top_boot_time
  result = { 'hw' => [], 'vm' => [], 'dc' => [] }
  threshold = { 'hw' => 600, 'vm' => 180, 'dc' => 60 }
  job_list = es_query_boot_job
  job_list.each do |job|
    testbox_type = job['testbox'][0, 2]
    testbox_type = 'hw' unless testbox_type.match?(/dc|vm/)
    boot_time = (Time.now - Time.parse(job['boot_time'])).to_i
    next if boot_time <= threshold[testbox_type]

    result[testbox_type] << { 'job_id' => job['id'], 'boot_time' => boot_time, 'result_root' => job['result_root'] }
  end
  result.each_key do |k|
    result[k].sort! { |a, b| b['boot_time'] <=> a['boot_time'] }
    result[k] = result[k][0..29] if result[k].length > 30
  end
  result.to_json
end

def top_boot_time
  begin
    body = get_top_boot_time
  rescue StandardError => e
    warn e.message
    return [500, headers.merge('Access-Control-Allow-Origin' => '*'), 'get top_boot_time error']
  end
  [200, headers.merge('Access-Control-Allow-Origin' => '*'), body]
end
