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
  condition_list = parse_argv(argv, common_conditions)
  matrices_list, suite_list = create_matrices_list(condition_list)
  compare_matrixes(matrices_list, suite_list, options: options)
end

def parse_argv(argv, common_conditions)
  conditions = []
  common_items = common_conditions.split(' ')
  argv.each do |item|
    items = item.split(' ') + common_items
    condition = parse_conditions(items)
    conditions << condition
  end
  conditions
end

def create_matrices_list(conditions)
  matrices_list = []
  suite_list = []
  es = ESQuery.new(ES_HOST, ES_PORT)
  conditions.each do |condition|
    query_results = es.multi_field_query(condition)
    matrix, suites = combine_query_data(query_results)
    matrices_list << matrix
    suite_list.concat(suites)
  end

  return matrices_list, suite_list
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
  conditions = parse_conditions(argv)
  dims = dimensions.split(' ')
  groups_matrices, suites_list = create_groups_matrices_list(conditions, dims)
  compare_group_matrices(groups_matrices, suites_list, options)
end

def create_groups_matrices_list(conditions, dims)
  es = ESQuery.new(ES_HOST, ES_PORT)
  query_results = es.multi_field_query(conditions)
  combine_group_query_data(query_results, dims)
end

# -------------------------------------------------------------------------------------------
# compare with user-defined compare_template.yaml
# compare_temlpate.yaml sample:
#   compare_metrics:
#        - fio.write_iops
#        - fio.read_iops
#   filter:
#        suite:
#                - fio-basic
#        os_arch:
#                - aarch64
#                - x86
#   compare_dimensions:
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

def compare_by_template(template)
  template_params = load_template(template)
  groups_matrices = create_groups_matrices(template_params)
  compare_results = compare_metrics_values(groups_matrices)
  show_compare_result(compare_results, template_params)
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
#   "compare_metrics"=>["fio.write_iops", "fio.read_iops"],
#   "filter"=>[
#     {"suite"=>["fio-bisic"]},
#     {"os_arch"=>["aarch_64"]}
#   ],
#   "compare_dimensions"=>[
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
  combine_group_jobs_list(
    query_results,
    template_params['x_params'],
    template_params['compare_dimensions'],
    template_params['compare_metrics']
  )
end
