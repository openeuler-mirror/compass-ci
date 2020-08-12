# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

# Exammple:
#   Input: jobs_list. The results of ES query.
#
#     eg: [ jobs1, jobs2, ...... ]
#
#     job: {suite => xxx, os => xxx, tbox_group => xxx, id => xxx, stats => xxx, ...}
#
#   Dimension: The dimensions you want to compare,  and the value will affect the test result
#
#     eg: os
#
#   output: grouped results.
#     eg:
#
#     {
#       'tbox_group=xxx/os_arch=xxx/os_version=23/pp.a.b=xxx' => {
#         'centos' => [job1, job2, ... ],
#         'debian' => [job3, job4, job5, ...]
#       },
#       ....
#     }
#

COMMON_PARAMS = %w[tbox_group os os_arch os_version].freeze

# ES search result auto grouping.
# @jobs_list: Array. job list.
# @dimensions: Array, compare key list.
def auto_group(jobs_list, dimensions)
  return if dimensions.empty?

  jobs_list = extract_jobs_list(jobs_list)
  groups = group(jobs_list, dimensions)
  return remove_singleton(groups)
end

def extract_jobs_list(jobs_list)
  jobs_list.map do |job|
    job['_source']
  end
end

def group(jobs_list, dimensions)
  groups = {}
  jobs_list.each do |job|
    group_params, dimension_key = get_group_dimension_params(job, dimensions)
    group_key = get_group_key(group_params)
    groups[group_key] ||= {}
    groups[group_key][dimension_key] ||= []
    next unless job['stats']

    groups[group_key][dimension_key] << job
  end
  filter_groups(groups)
  groups
end

def filter_groups(groups)
  groups.each do |group_key, value|
    value.each_key do |dim_key|
      value.delete(dim_key) if value[dim_key].empty?
    end
    groups.delete(group_key) if groups[group_key].empty?
  end
end

def get_all_params(job)
  all_params = {}
  job.each_key do |param|
    all_params[param] = job[param] if COMMON_PARAMS.include?(param)
    next unless param == 'pp'

    pp_params = get_pp_params(job[param])
    pp_params.each do |k, v|
      all_params[k] = v
    end
  end
  all_params
end

def get_pp_params(pp_params)
  pp = {}
  pp_params.each do |k, v|
    next unless v.is_a?(Hash)

    v.each do |inner_key, inner_value|
      pp[['pp', k, inner_key].join('.')] = inner_value
    end
  end
  pp
end

def get_group_dimension_params(job, dimensions)
  all_group_params = get_all_params(job)
  dimension_list = []
  dimensions.each do |dimension|
    dimension_list << all_group_params.delete(dimension) if all_group_params.key?(dimension)
  end
  [all_group_params, dimension_list.join('|')]
end

def get_group_key(group_params)
  group_str = group_params.each.map do |k, v|
    "#{k}=#{v}"
  end.sort!.join('/')
  return group_str
end

def remove_singleton(groups)
  groups.delete_if { |_k, v| v.length < 2 }
end
