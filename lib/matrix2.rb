# SPDX-License-Identifier: GPL-2.0-only

# frozen_string_literal: true

LKP_SRC ||= ENV['LKP_SRC'] || '/c/lkp-tests'

require "#{LKP_SRC}/lib/stats"
require "#{LKP_SRC}/lib/yaml"
require "#{LKP_SRC}/lib/matrix"
require_relative './params_group.rb'

def set_pre_value(item, value, sample_size)
  return value if item.end_with?('.message', '.log', '.element')

  if value.size == 1
    value[0]
  elsif independent_counter? item
    value.sum
  elsif event_counter? item
    value[-1] - value[0]
  else
    value.sum / sample_size
  end
end

def extract_pre_result(stats, monitor, file)
  monitor_stats = load_json file # yaml.load_json
  sample_size = max_cols(monitor_stats)

  monitor_stats.each do |k, v|
    next if k == "#{monitor}.time"

    stats[k] = set_pre_value(k, v, sample_size)
    stats[k + '.max'] = v.max if should_add_max_latency k
  end
end

def file_check(file)
  case file
  when /\.json$/
    File.basename(file, '.json')
  when /\.json\.gz$/
    File.basename(file, '.json.gz')
  end
end

def create_stats(result_root)
  stats = {}

  monitor_files = Dir["#{result_root}/*.{json,json.gz}"]

  monitor_files.each do |file|
    next unless File.size?(file)

    monitor = file_check(file)
    next if monitor == 'stats'

    extract_pre_result(stats, monitor, file)
  end

  save_json(stats, result_root + '/stats.json') # yaml.save_json
  # stats
end

module Matrix
  # input: job_list
  # return: matrix of Hash(String, Array(Number))
  #   Eg: matrix: {
  #                 test_params_1 => [value_1, value_2, ...],
  #                 test_params_2 => [value_1, value_2, ...],
  #                 test_params_3 => [value_1, 0, ...]
  #                 ...
  #               }
  def self.create_matrix(job_list)
    matrix = {}
    suites = []
    job_list.each do |job|
      stats = job['stats']
      suites << job['suite']

      stats.each do |key, value|
        next if key.include?('timestamp')
        next if useless_stat?(key)

        matrix[key] = [] unless matrix[key]
        matrix[key] << value
      end
    end

    return matrix, suites
  end

  def self.useless_stat?(stat)
    return unless @fields

    @fields.each do |field|
      return false if stat.include?(field)
    end

    true
  end

  # input: query results from es_query
  # return: matrix
  def self.combine_query_data(query_data, options)
    job_list = extract_jobs_list(query_data['hits']['hits'])
    return nil if job_list.size < options[:min_samples]

    @fields = options[:fields]
    create_matrix(job_list)
  end

  # input: query results from es_query
  # return: group_matrix of Hash(String, Hash(String, matrix))
  #   Eg: group_matrix: {
  #                 group1_key => { dimension_1 => matrix
  #                                 dimension_2 => matrix
  #                                ...
  #                 group2_key => {...}
  #                 ...
  #               }
  def self.combine_group_query_data(job_list, dims, options)
    @fields = options[:fields]
    suites_hash = {}
    latest_jobs_hash = {}
    groups = auto_group(job_list, dims)
    have_multi_member = multi_member?(groups)
    one_size_count = 0
    groups.each do |group_key, value|
      if value.size < 2
        one_size_count += 1
        next if group_deleted?(groups, group_key, have_multi_member, one_size_count)
      end
      get_groups_matrix(groups, group_key, value, suites_hash, latest_jobs_hash)
    end
    return nil if groups.empty?

    return groups, suites_hash, latest_jobs_hash
  end

  def self.group_deleted?(groups, group_key, have_multi_member, one_size_count)
    was_deleted = false
    if have_multi_member || one_size_count > 3
      groups.delete(group_key)
      was_deleted = true
    end

    was_deleted
  end

  def self.get_groups_matrix(groups, group_key, value, suites_hash, latest_jobs_hash)
    suite_list = []
    latest_jobs_hash[group_key] = []
    value.each do |dimension_key, jobs|
      groups[group_key][dimension_key], suites = create_matrix(jobs)
      suite_list.concat(suites)
      latest_jobs_hash[group_key] << jobs[0]
    end
    suites_hash[group_key] = suite_list
  end

  def self.multi_member?(groups)
    groups.each do |_key, value|
      return true if value.size > 1
    end
    return false
  end

  # input:
  #   1. query results(job_list) from es_query that will be auto group by auto_group_by_template()
  #   2. params from user's template include:
  #       groups_params(x_params):
  #         eg: ['block_size', 'package_size']
  #       dimensions:
  #         eg: [
  #               {'os' => 'openeuler', 'os_version' => '20.03'},
  #               {'os' => 'centos', 'os_version' => '7.6'}
  #            ]
  #       metrics:
  #         eg: ['fio.read_iops', 'fio_write_iops']
  # return: group_matrix of Hash(String, Hash(String, matrix))
  def self.combine_group_jobs_list(query_data, groups_params, dimensions, metrics)
    job_list = query_data['hits']['hits']
    groups = auto_group_by_template(job_list, groups_params, dimensions, metrics)
    groups.each do |group_key, dims|
      dims.each do |dim_key, jobs|
        groups[group_key][dim_key], = create_matrix(jobs)
      end
    end

    groups
  end
end
