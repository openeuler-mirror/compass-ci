# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

# Example:
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
  return [] if dimensions.empty?

  jobs_list = extract_jobs_list(jobs_list)
  group(jobs_list, dimensions)
end

def extract_jobs_list(jobs_list)
  jobs_list.map! do |job|
    job['_source'] if job_is_useful?(job)
  end

  jobs_list.compact
end

def job_is_useful?(job)
  stats = job['_source']['stats']
  return unless stats

  suite = job['_source']['suite']
  return unless suite

  true
end

def group(jobs_list, dimensions)
  groups = {}
  jobs_list.each do |job|
    group_params, dimension_key = get_group_dimension_params(job, dimensions)
    group_key = get_group_key(group_params)
    groups[group_key] ||= {}
    groups[group_key][dimension_key] ||= []
    groups[group_key][dimension_key] << job
  end
  filter_groups(groups)
  groups
end

def filter_groups(groups)
  groups.each do |group_key, value|
    if value.empty?
      groups.delete(group_key)
      next
    end
    value.delete_if { |_dim_key, job_list| job_list.empty? }
  end
end

def get_tbox_group(tbox_group)
  return tbox_group.gsub(/(--|\.).*$/, '')
end

def get_all_params(job)
  all_params = {}
  job.each_key do |param|
    all_params[param] = job[param] if COMMON_PARAMS.include?(param)
    all_params[param] = get_tbox_group(job[param]) if param == 'tbox_group'
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
    all_group_params.delete('os_version') if dimension == 'os'
  end
  [all_group_params, dimension_list.join('|')]
end

def get_group_key(group_params)
  group_str = group_params.each.map do |k, v|
    "#{k}=#{v}"
  end.sort!.join(' ')
  return group_str
end

def remove_singleton(groups)
  groups.delete_if { |_k, v| v.length < 2 }
end

# --------------------------------------------------------------------------------------------------
# auto_group_by_template: auto group job_list by user's template
# Example:
#   Input:
#     1. jobs_list.
#     2. params from user's template that include:
#       groups_params(x_params):
#         eg: ['block_size', 'package_size']
#       dimensions:
#         eg: [
#               {'os' => 'openeuler', 'os_version' => '20.03'},
#               {'os' => 'centos', 'os_version' => '7.6'}
#            ]
#       metrics:
#         eg: ['fio.read_iops', 'fio_write_iops']
#   Output:
#     eg:
#       {
#         '4K|1G' => {
#           'openeuler 20.03' => [
#             {'stats' => {'fio.write_iops' => 312821.002387, 'fio.read_iops' => 212821.2387}},
#             {'stats' => {'fio.write_iops' => 289661.878453}},
#             ...
#           ],
#           'centos 7.6' => [...]
#         },
#         '16K|1G' => {...},
#         ...
#       }

def auto_group_by_template(jobs_list, group_params, dimensions, metrics)
  jobs_list = extract_jobs_list(jobs_list)
  get_group_by_template(jobs_list, group_params, dimensions, metrics)
end

def get_group_by_template(job_list, group_params, dimensions, metrics)
  groups = {}
  job_list.each do |job|
    new_job = get_new_job(job, metrics)
    next if new_job.empty?

    group_key = get_user_group_key(job, group_params)
    dimension = get_user_dimension(job, dimensions)
    next unless group_key && dimension

    groups[group_key] ||= {}
    groups[group_key][dimension] ||= []
    groups[group_key][dimension] << new_job
  end

  groups
end

# @group_params Array(String)
# eg:
#   ['block_size', 'package_size']
# return eg:
#   '4K|1G'
def get_user_group_key(job, group_params)
  group_key_list = []
  group_params.each do |param|
    value = find_param_in_job(job, param)
    group_key_list << value if value
  end
  return nil if group_key_list.size < group_params.size || group_key_list.empty?

  group_key_list.join('|')
end

def find_param_in_job(job, param)
  return job[param] if job.key?(param)

  # handle pp.* params
  job['pp'].each_value do |v|
    next unless v.is_a?(Hash)

    return v[param] if v.key?(param)
  end

  return nil
end

# @dimension Array(Hash)
# eg:
#   [
#     {os => openeuler, os_version => 20.03},
#     {os => centos, os_version => 7.6}
#   ]
#  return eg:
#    'openeuler 20.03'
def get_user_dimension(job, dimensions)
  dimension_list = []
  dimensions.each do |dim|
    dim.each do |key, value|
      if job[key] == value
        dimension_list << value
      end
    end
    return nil if !dimension_list.empty? && dimension_list.size < dim.size
  end
  return nil if dimension_list.empty?

  dimension_list.join(' ')
end

# @metrics Array(String)
# eg:
#   ["fio.read_iops", "fio.write_iops"]
# return new_job
# eg:
#   {'stats' => {'fio.write_iops' => 312821.002387, 'fio.read_iops' => 212821.2387}},
def get_new_job(job, metrics)
  return {} unless job['stats']

  new_job = {'stats' => {}}
  if metrics.empty?
    suite = job['suite']
    job['stats'].each_key do |key|
      new_job['stats'][key] = job['stats'][key] if key.start_with?(suite)
    end
  else
    metrics.each do |metric|
      if job['stats'].key?(metric)
        new_job['stats'][metric] = job['stats'][metric]
      end
    end
  end

  new_job
end
