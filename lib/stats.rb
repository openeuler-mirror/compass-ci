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
  available_stats = {}
  Dir.open(LKP_SRC + '/stats').each do |file|
    next if file.start_with?('.')
    name = File.basename file, '.rb'
    available_stats[name] = LKP_SRC + '/stats/' + file
  end

  Dir.glob("#{LKP_SRC}/programs/*/parse*").each do |path|
    next unless File.executable? path
    name = File.basename path, '.rb'
    if name == 'parse'
      name = File.basename(File.dirname(path))
    else
      name.sub!(/^parse-/, '')
    end
    available_stats[name] = path
  end

  available_stats
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
    @available_stats = available_stats
  end

  def extract_stats
    stats_list = assign_stats_list
    stats_list.each do |stat|
      next unless @available_stats.include?(stat)
      file = @available_stats[stat]
      if file.end_with?('.rb')
        StatsWrapper.wrapper_func(file, *stat)
      else
        StatsWrapper.wrapper(file, *stat)
      end
    end
  end

  def assign_stats_list
    stats_list = Set.new
    stats_list << ['time', @job['suite'] + '.time']

    @job['pp'] ||= {}
    @job['monitors'] ||= {}
    programs = @job['pp'].keys + @job['monitors'].keys
    programs.each do |k|
      if @available_stats.include?(k)
        stats_list << k
      end
    end

    assign_default_stats(stats_list)

    stats_list
  end
end
