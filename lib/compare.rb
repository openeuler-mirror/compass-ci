# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require_relative './es_query.rb'
require_relative './matrix2.rb'
require_relative './compare_matrixes.rb'
require_relative './constants.rb'

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
  matrices_list = create_matrices_list(condition_list)
  compare_matrixes(matrices_list, options: options)
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
  es = ESQuery.new(ES_HOST, ES_PORT)
  conditions.each do |condition|
    query_results = es.multi_field_query(condition)
    matrices_list << combine_query_data(query_results)
  end
  matrices_list
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
  groups_matrices = create_groups_matrices_list(conditions, dims)
  compare_group_matrices(groups_matrices, options)
end

def create_groups_matrices_list(conditions, dims)
  es = ESQuery.new(ES_HOST, ES_PORT)
  query_results = es.multi_field_query(conditions)
  combine_group_query_data(query_results, dims)
end
