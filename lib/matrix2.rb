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
