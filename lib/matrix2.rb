#!/usr/bin/env ruby

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require "#{LKP_SRC}/lib/stats"
require "#{LKP_SRC}/lib/yaml"
require "#{LKP_SRC}/lib/matrix"

def create_stats(result_root)
  stats = {}

  monitor_files = Dir["#{result_root}/*.{json,json.gz}"]

  monitor_files.each do |file|
    next unless File.size?(file)

    case file
    when /\.json$/
      monitor = File.basename(file, '.json')
    when /\.json\.gz$/
      monitor = File.basename(file, '.json.gz')
    end

    next if monitor == 'stats' # stats.json already created?

    monitor_stats = load_json file#yaml.load_json
    sample_size = max_cols(monitor_stats)

    monitor_stats.each do |k, v|
      next if k == "#{monitor}.time"

      stats[k] = if v.size == 1
                   v[0]
                 elsif independent_counter? k
                   v.sum
                 elsif event_counter? k
                   v[-1] - v[0]
                 else
                   v.sum / sample_size
                 end
      stats[k + '.max'] = v.max if should_add_max_latency k
    end
  end

  save_json(stats, result_root + '/stats.json')#yaml.save_json
#  stats
end

