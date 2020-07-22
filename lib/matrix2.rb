# SPDX-License-Identifier: GPL-2.0-only

# frozen_string_literal: true

LKP_SRC = ENV['LKP_SRC'] || '/c/lkp-tests'

require "#{LKP_SRC}/lib/stats"
require "#{LKP_SRC}/lib/yaml"
require "#{LKP_SRC}/lib/matrix"

def set_pre_value(item, value, sample_size)
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
    next if monitor == 'stats' # stats.json already created?

    extract_pre_result(stats, monitor, file)
  end

  save_json(stats, result_root + '/stats.json') # yaml.save_json
  # stats
end

def samples_fill_missing_zeros(value, size)
  samples = value || [0] * size
  samples << 0 while samples.size < size
  samples
end

# input: query results from es-find
# return: Hash(String, Array(Number))
#   Eg: matrix :{
#                 test_params_1 => [value_1, value_2, ...],
#                 test_params_2 => [value_1, value_2, ...],
#                 test_params_3 => [value_1, 0, ...]
#                 ...
#               }
def combine_query_data(query_data)
  job_results = query_data['hits']['hits']
  matrix = {}
  job_results.each do |job|
    stats = job['_source']['stats']
    next unless stats

    stats.each do |key, value|
      next if key =~ /^stderr/
      matrix[key] = [] unless matrix[key]
      matrix[key] << value
    end
  end
  col_size = job_results.size
  matrix.each_value do |value|
    samples_fill_missing_zeros(value, col_size)
  end
  matrix
end
