# SPDX-License-Identifier: GPL-2.0-only

# frozen_string_literal: true

require_relative './stats_wrapper'

def load_yaml(path)
  unless File.file?(path)
    warn "#{path} does not exist"
    exit
  end
  YAML.load_file(path)
end

def available_stats
  vailable_stats = []
  available_stats_func = []
  Dir.open(LKP_SRC + '/stats').each do |file|
    next if file.start_with?('.')

    if file.end_with?('.rb')
      available_stats_func << file.chomp('.rb')
    else
      vailable_stats << file
    end
  end

  [vailable_stats, available_stats_func]
end

def assign_default_stats(stats_list)
  default_stats = YAML.load_file(LKP_SRC + '/etc/default_stats.yaml').keys
  default_stats.each { |stat| stats_list << stat }
end

# extract each result from the script output
# format each result as $script.json
class Stats
  def initialize(result_root)
    @result_root = result_root
    @job = load_yaml(File.join(result_root, 'job.yaml'))
    @available_stats, @available_stats_func = available_stats
  end

  def extract_stats
    stats_list = assign_stats_list
    stats_list.each do |stat|
      if @available_stats_func.include?(stat)
        StatsWrapper.wrapper_func(*stat)
      else
        StatsWrapper.wrapper(*stat)
      end
    end
  end

  def assign_stats_list
    stats_list = Set.new
    stats_list << @job['suite']
    stats_list << ['time', @job['suite'] + '.time']
    stats_list << 'stderr'
    @job.each_key do |k|
      if @available_stats.include?(k) || @available_stats_func.include?(k)
        stats_list << k
      end
    end
    assign_default_stats(stats_list)

    stats_list
  end
end
