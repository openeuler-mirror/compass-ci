# SPDX-License-Identifier: MulanPSL-2.0+ or GPL-2.0
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require_relative './es_query.rb'
require_relative './matrix2.rb'
require_relative './manticore.rb'
require_relative './compare_matrixes.rb'
require_relative './constants.rb'
require 'yaml'

# -------------------------------------------------------------------------------------------
# compare_matrices_list
# - 2 conditions at least
# - each conditions will be parsed to query_fields for es_query
# - option: common_conditions, which are same with conditions will be merged with each conditions
# conditions sample:
# - single conditions: "id=6001"
# - multiple conditions: "os=centos,debian suite=iperf,atomic"
#

def compare_matrices_list(argv, common_conditions, options)
  conditions = parse_argv(argv, common_conditions)
  matrices_list, suite_list, titles = create_matrices_list(conditions, options)
  if matrices_list.size < 2
    return nil if options[:no_print]

    warn 'matrix less than min_samples'
  end

  compare_matrixes(matrices_list, suite_list, nil, titles, options: options)
end

def safe_multi_field_query(query, **opts)
  es = ESQuery.new
  begin
    result = es.multi_field_query(query, **opts)
    if result.nil? || result['hits'].nil? || result['hits']['hits'].empty?
      raise 'No ES result'
    end
    result
  rescue
    # 直接使用 QueryBuilder 构建查询
    builder = Manticore::QueryBuilder.new(index: Manticore::DEFAULT_INDEX, size: opts[:size] || 10_000)
    
    # 处理查询条件
    if query.is_a?(Hash)
      query.each do |k, v|
        builder.add_filter(k, Array(v))
      end
    elsif query.is_a?(String)
      # 处理 key=val1,val2 格式的查询字符串
      field, values = query.split('=', 2)
      builder.add_filter(field, values.split(',')) if field && values
    end

    # 添加排序
    builder.sort(opts[:desc_keyword] || 'submit_time', order: 'desc')
    
    # 执行查询并格式化结果
    response = Manticore::Client.search(builder.build)
    body = JSON.parse(response.body)
    hits = (body['hits'] && body['hits']['hits']) || []
    { 'hits' => { 'hits' => hits } }
  end
end

def parse_argv(argv, common_conditions)
  conditions = []
  common_items = common_conditions.split(' ')
  argv.each do |item|
    items = item.split(' ') + common_items
    condition = parse_conditions(items)
    conditions << [item, condition]
  end
  conditions
end

def create_matrices_list(conditions, options)
  matrices_list = []
  suite_list = []
  titles = []
  conditions.each do |condition|
    query_results = safe_multi_field_query(condition[1], desc_keyword: 'start_time')
    matrix, suites = Matrix.combine_query_data(query_results, options)
    next unless matrix

    matrices_list << matrix
    titles << condition[0]
    suite_list.concat(suites)
  end

  return matrices_list, suite_list, titles
end

# -------------------------------------------------------------------------------------------
# compare_group
# - one condition only
# - condition can be parsed to query_fields for es_query
# - option: dimensions required, used for auto_group
# dimensions sample:
# - single dimension: "os"
# - multiple dimensions: "os os_version ..."
#

def compare_group(argv, dimensions, options)
  options[:dims] = dimensions.split(',').join('|')
  conditions = parse_conditions(argv)
  dims = dimensions.split(' ')
  groups_matrices, suites_hash, latest_jobs_hash = create_groups_matrices_list(conditions, dims, options)
  unless groups_matrices
    warn 'Empty group matrices!'
    exit
  end
  compare_group_matrices(groups_matrices, suites_hash, latest_jobs_hash, options)
end

def create_groups_matrices_list(conditions, dims, options)
  query_results = safe_multi_field_query(conditions, desc_keyword: 'start_time')
  Matrix.combine_group_query_data(query_results['hits']['hits'], dims, options)
end

# -------------------------------------------------------------------------------------------
# compare with user-defined compare_template.yaml
# compare_temlpate.yaml sample:
#   metrics:
#        - fio.write_iops
#        - fio.read_iops
#   filter:
#        suite:
#                - fio-basic
#        os_arch:
#                - aarch64
#                - x86
#   series:
#        - os: debian
#          os_version: sid
#        - os: openeuler
#          os_version: 20.03
#   x_params:
#        - bs
#        - test_size
#   title: Hackbench Performance Testing
#   unit: KB/s
#

def compare_by_template(template, _options)
  template_params = load_template(template)
  groups_matrices = create_groups_matrices(template_params)
  cmp_series = combine_compare_dims(template_params['series'])
  result = {}
  groups_matrices.each do |group, group_matrices|
    compare_results = compare_metrics_values(group_matrices, cmp_series)
    formatter = FormatEchartData.new(compare_results, request_body, group, cmp_series)
    echart_data = formatter.format_echart_data(transposed)
    result[group] = echart_data
  end
  result
end

def load_template(template)
  unless File.file?(template)
    warn 'template does not exist'
    exit
  end
  YAML.load_file(template)
end

# input: template_params: Hash
# eg:
# {
#   "metrics"=>["fio.write_iops", "fio.read_iops"],
#   "filter"=>[
#     {"suite"=>["fio-bisic"]},
#     {"os_arch"=>["aarch_64"]}
#   ],
#   "series"=>[
#     {"os"=>"openeuler", "os_version"=>20.03},
#     {"os"=>"centos", "os_version"=>7.6}
#   ],
#   "x_params"=>["block_size", "package_size"],
#   "title"=>"Hackbench Performance Testing",
#   "unit"=>"KB/s"
# }
def create_groups_matrices(template_params)
  es = ESQuery.new
  if template_params.key?('max_series_num') && template_params['max_series_num'] > 0
    max_job_num = template_params['max_series_num'] * 200
    query_results = es.multi_field_query(template_params['filter'], size: max_job_num, desc_keyword: 'start_time')
  else
    query_results = es.multi_field_query(template_params['filter'], desc_keyword: 'start_time')
  end
  job_list = query_results['hits']['hits']
  groups, cmp_series = create_group_jobs(template_params, job_list)

  new_groups = {}
  common_group_key = {}
  group_testbox = {}
  common_group_key = extract_common_group_key(groups.keys) if groups.size > 1
  test_params = template_params['test_params'] || nil

  groups.each do |first_group_key, first_group|
    new_group = create_new_key(first_group_key, common_group_key, template_params['series'], test_params)
    group_testbox[new_group] = first_group['testbox']
    first_group.delete('testbox')
    new_groups[new_group] = Matrix.combine_group_jobs_list(first_group)
  end

  return new_groups, cmp_series, group_testbox
end

def create_new_key(first_group_key, common_group_key, series, test_params)
  new_group_key = Set.new(first_group_key.split) ^ common_group_key
  if common_group_key.empty?
    if test_params
      new_group_key.delete_if { |item| need_delete?(item, test_params) }
    else
      if new_group_key.size > 4
        new_group_key.delete_if { |item| !item.start_with?('pp') }
      else
        new_group_key.delete_if { |item| item.start_with?('os_version', 'os=') }
      end
    end
  else
    series.each do |item|
      next unless item.is_a?(Hash)

      item.each do |k, v|
        param = "#{k}=#{v}"
        new_group_key.delete(param) if new_group_key.include?(param)
      end
    end
  end

  new_group = new_group_key.to_a.join(' ')
end

def need_delete?(item, test_params)
  test_params.each do |param|
    return false if item.include?(param)
  end
  true
end

# input:
# [
#   "os_arch=aarch64 pp.stream.array_size=50000000 pp.stream.nr_threads=32"
#   "os_arch=aarch64 pp.stream.array_size=50000000 pp.stream.nr_threads=128"
#   ...
# ]
# return:
# [ "os_arch=aarch64", "pp.stream.array_size=50000000"]
def extract_common_group_key(group_keys)
  common_params = group_keys[0].split
  group_keys.each do |group_key|
    common_params &= group_key.split
  end

  Set.new(common_params)
end

def create_group_jobs(template_params, job_list)
  cmp_series = []

  # if user haven't give the detail compare_seriesm just give the seies key
  #   "series"=>["group_id"],
  # we will get few latest dimensions by such series,
  # and there should be a max_series_num for get how many dimension
  if template_params.key?('max_series_num') && template_params['max_series_num'] > 0
    groups, cmp_series = auto_group_by_template(
      job_list,
      template_params['x_params'],
      template_params['series'],
      template_params['metrics'],
      template_params['max_series_num']
    )
  else
    groups, = auto_group_by_template(job_list, template_params['x_params'], template_params['series'], template_params['metrics'])
  end

  return groups, cmp_series
end

# input eg:
#   [{"os" => "openeuler", "os_version" => "20.03"}, {"os" => "centos", "os_version" => "7.6"}]
# return eg:
#   ["openeuler 20.03", "centos 7.6"]
def combine_compare_dims(dims)
  cmp_dims = []
  dims.each do |dim|
    cmp_dim = ''
    dim.each_value do |v|
      cmp_dim += " #{v}"
    end
    cmp_dims << cmp_dim.strip
  end

  cmp_dims
end
