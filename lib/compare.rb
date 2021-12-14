# SPDX-License-Identifier: MulanPSL-2.0+ or GPL-2.0
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require_relative './es_query.rb'
require_relative './matrix2.rb'
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

    warn "matrix less than min_samples"
  end

  compare_matrixes(matrices_list, suite_list, nil, titles, options: options)
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
  es = ESQuery.new
  conditions.each do |condition|
    query_results = es.multi_field_query(condition[1], desc_keyword: 'start_time')
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
  es = ESQuery.new
  query_results = es.multi_field_query(conditions, desc_keyword: 'start_time')
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

def compare_by_template(template, options)
  template_params = load_template(template)
  groups_matrices = create_groups_matrices(template_params)
  cmp_series = combine_compare_dims(template_params['series'])
  result = {}
  groups_matrices.each do |group, group_matrices|
    compare_results = compare_metrics_values(group_matrices, cmp_series)
    formatter = FormatEchartData.new(compare_results, request_body, cmp_series)
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
  query_results = es.multi_field_query(template_params['filter'])
  job_list = query_results['hits']['hits']
  groups = auto_group_by_template(job_list, template_params['x_params'], template_params['series'], template_params['metrics'])
  groups.each do |first_group_key, first_group|
    groups[first_group_key] = Matrix.combine_group_jobs_list(first_group)
  end

  groups
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
