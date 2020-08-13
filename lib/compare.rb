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

def compare_matrices_list(argv, common_conditions)
  condition_list = parse_argv(argv, common_conditions)
  matrices_list = create_matrices_list(condition_list)
  compare_matrixes(matrices_list)
end

def parse_argv(argv, common_conditions)
  conditions = []
  argv.each do |item|
    item += ' ' + common_conditions unless common_conditions.nil?
    items = item.split(' ')
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
