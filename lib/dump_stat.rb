# SPDX-License-Identifier: GPL-2.0-only

LKP_SRC ||= ENV['LKP_SRC'] || '/c/lkp-tests'

require "#{LKP_SRC}/lib/statistics"
require "#{LKP_SRC}/lib/bounds"
require "#{LKP_SRC}/lib/yaml"
require "#{LKP_SRC}/lib/job"
require "#{LKP_SRC}/lib/string_ext"
require 'set'

UNSTRUCTURED_MONITORS = %w[ftrace].to_set

# dump stat which input by lkp-tests/stats/$script return
# input:
#   eg-1:
#     {
#       "pgfree" => [275506, 280018],
#       ...
#     }
#   eg-2:
#     {
#       "iperf.tcp.sender.bps" => 34804801216.197174,
#       "iperf.tcp.receiver.bps" => "34804762215.18231"
#     }
module DumpStat
  def self.dump_stat(monitor, stat_result)
    @result = {}
    @invalid_records = []
    @record_index = 0
    @monitor = monitor

    stat_result.each do |key, value|
      key = key.resolve_invalid_bytes
      key = key.strip
      next if key[0] == '#'
      next if value.empty? || value == 0
      next if monitor =~ /^(dmesg|kmsg)$/ && key =~ /^(message|pattern):/

      if key =~ /[ \t]/
        @invalid_records.push @record_index
        log_warn({
                   'message' => "whitespace in stats name: #{key}",
                   'error_message' => "whitespace in stats name: #{key}, check #{RESULT_ROOT}/#{@monitor}"
                 })
        return nil # for exit current stats/script dump-stat
      end
      next if assign_log_message(key, value)

      k = @monitor + '.' + key
      @result[k] ||= []
      fill_zero(k)
      if value.is_a?(String)
        value = check_string_value(k, value, @monitor)
        next  unless value
        return nil unless number?(k, value, @invalid_records, @record_index, @monitor)

        value = value.index('.') ? value.to_f : value.to_i
      elsif value.is_a?(Array)
        (0..value.size - 1).each do |i|
          next unless value[i].is_a?(String)

          value[i] = check_string_value(k, value[i], @monitor)
          next unless value[i]
          return nil unless number?(k, value[i], @invalid_records, @record_index, @monitor)

          value[i] = value[i].index('.') ? value[i].to_f : value[i].to_i
          valid_stats_verification(k, value[i])
        end
        @result[k] = value
        next
      end
      valid_stats_verification(k, value)
      @result[k].push value
    end
    return nil if @result.empty?

    remove_zero_stats
    delete_invalid_number(@result, @invalid_records, @monitor)
    cols_verifation
    return nil unless useful_result?(@result)

    save_json(@result, "#{RESULT_ROOT}/#{@monitor}.json", compress: (@result.size * @min_cols > 1000))
  end

  # keep message | log line which key end with .message|.log
  def self.assign_log_message(key, value)
    if key.starts_with?('msg.', 'log.', 'element.') ||
       key.end_with?('.message', '.log', '.element')
      k = @monitor + '.' + key
      @result[k] = value
      return true
    end

    false
  end

  def self.fill_zero(key)
    size = @result[key].size
    if @record_index < size
      @record_index = size
    elsif (@record_index - size).positive?
      # fill 0 for missing values
      @result[key].concat([0] * (@record_index - size))
    end
  end

  def self.valid_stats_verification(key, value)
    return nil if valid_stats_range? key, value

    @invalid_records.push @record_index
    puts "outside valid range: #{value} in #{key} #{RESULT_ROOT}"
  end

  def self.remove_zero_stats
    @max_cols = 0
    @min_cols = Float::INFINITY
    @min_cols_stat = ''
    @max_cols_stat = ''
    zero_stats = []
    @result.each do |key, val|
      if @max_cols < val.size
        @max_cols = val.size
        @max_cols_stat = key
      end
      if @min_cols > val.size
        @min_cols = val.size
        @min_cols_stat = key
      end
      next if val[0] != 0
      next if val[-1] != 0
      next if val.sum != 0

      zero_stats << key
    end
    zero_stats.each { |x| @result.delete x }
  end

  def self.cols_verifation
    return nil unless @min_cols < @max_cols && !UNSTRUCTURED_MONITORS.include?(@monitor)

    if @min_cols == @max_cols - 1
      @result.each { |_k, y| y.pop if y.size == @max_cols }
      puts "Last record seems incomplete. Truncated #{RESULT_ROOT}/#{@monitor}.json"
    else
      log_warn({
                 'message' => 'Not a matrix: value size is different',
                 'error_message' => "Not a matrix: value size is different - #{@min_cols_stat}: #{@min_cols} != #{@max_cols_stat}: #{@max_cols}: #{RESULT_ROOT}/#{@monitor}.json, #{@monitor}"
               })
    end
  end
end

def check_string_value(key, value, monitor)
  value.strip!
  if value.empty?
    log_warn({
               'message' => "empty stat value of #{key}",
               'error_message' => "empty stat value of #{key}, check #{RESULT_ROOT}/#{monitor}"
             })
    return nil
  end

  return value
end

# only number is valid
def number?(key, value, invalid_records, record_index, monitor)
  unless value.numeric?
    invalid_records.push record_index
    log_warn({
               'message' => 'invalid stats key-value',
               'error_message' => "invalid stats key-value: key: #{key}, value: #{value}, check #{RESULT_ROOT}/#{monitor}"
             })
    return nil
  end

  true
end

def delete_invalid_number(result, invalid_records, monitor)
  return nil if monitor == 'ftrace'

  invalid_records.reverse_each do |index|
    result.each do |_k, value|
      value.delete_at index
    end
  end
end

def useful_result?(result)
  return nil if result.empty?
  return nil if result.values[0].size.zero?
  return nil if result.values[-1].size.zero?

  true
end
