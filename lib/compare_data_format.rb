# SPDX-License-Identifier: MulanPSL-2.0+ or GPL-2.0
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'terminal-table'

# ----------------------------------------------------------------------------------------------------
# format compare results for a specific format
#
class FormatEchartData
  def initialize(compare_results, template_params, dims = {})
    @compare_results = compare_results
    @template_params = template_params
    @dims = dims
    @data_set = {}
  end

  def format_for_echart
    echart_result = {}
    echart_result['title'] = @template_params['title']
    echart_result['unit'] = @template_params['unit']
    @x_name = @template_params['x_params']
    echart_result['x_name'] = @x_name.join('|') if @x_name
    echart_result['tables'] = convert_to_echart_dataset

    echart_result
  end

  def convert_to_echart_dataset
    @x_params = sort_x_params(@compare_results.keys)
    @compare_results.each_value do |metrics_values|
      metrics_values.each do |metric, metric_value|
        assign_echart_data_set(metric, metric_value)
      end
    end

    @data_set
  end

  def assign_echart_data_set(metric, metric_value)
    @data_set[metric] = {}
    metric_value.each do |value_type, values| # value_type can be: average, standard_deviation, change
      @data_set[metric][value_type] = {
        'dimensions' => ['dimensions']
      }

      dimension_list = values.keys.sort
      @data_set[metric][value_type]['dimensions'] += dimension_list
      @data_set[metric][value_type]['source'] = assign_echart_source(metric, value_type, dimension_list)
    end
  end

  def assign_echart_source(metric, value_type, dimensions)
    source = []
    source << @x_params.clone
    dimensions.each do |dimension|
      dimension_values = [dimension]
      @x_params.each do |x_param|
        if @compare_results[x_param][metric] && @compare_results[x_param][metric][value_type]
          dimension_values << @compare_results[x_param][metric][value_type][dimension]
        else
          source[0].delete(x_param)
        end
      end
      source << dimension_values
    end

    source
  end

  # -------------------------------------------------------------------------------------------------
  # format data for api
  # output:
  # [
  #   {
  #     "title": "iperf.tcp.sender.bps",
  #     "datas": [
  #       {
  #         "name": "openeuler",
  #         "data": [22690569006.73847, 26416908414.62344, ...]
  #         "deviation": [15.41451513296539, 22.716525982147182, ...],
  #         "x_params": [ "10", "20", ...]
  #       },
  #       {...},
  #     ]
  #   },
  #   ...
  # ]
  # -------------------------------------------------------------------------------------------------
  def format_echart_data
    # kv[0]: x_param
    # kv[1]: metrics_vaules
    sort_compare_result(@compare_results).each do |kv|
      kv[1].each do |metric, values|
        @data_set[metric] ||= {}
        @data_set[metric]['title'] = metric
        @data_set[metric]['datas'] ||= {}
        assign_datas(kv[0], metric)
      end
    end

    convert_echart_line_data
  end

  def assign_datas(x_param, metric)
    @dims.each do |dim|
      @data_set[metric]['datas'][dim] ||= {}
      @data_set[metric]['datas'][dim]['name'] = dim
      @data_set[metric]['datas'][dim]['data'] ||= []
      @data_set[metric]['datas'][dim]['deviation'] ||= []
      @data_set[metric]['datas'][dim]['x_params'] ||= []

      @data_set[metric]['datas'][dim]['x_params'] << x_param
      @data_set[metric]['datas'][dim]['data'] << assign_data(x_param, metric, 'average', dim)
      @data_set[metric]['datas'][dim]['deviation'] << assign_data(x_param, metric, 'standard_deviation', dim)
    end
  end

  def assign_data(x_param, metric, type, dim)
    return 0 unless @compare_results[x_param].key?(metric)
    return 0 unless @compare_results[x_param][metric][type].key?(dim)
    return @compare_results[x_param][metric][type][dim]
  end

  def convert_echart_line_data
    echart_data = []
    @data_set.each_value do |metric_values|
      datas = {}
      metric_values.each do |key, value|
        if key != 'datas'
          datas.merge!({key => value})
          next
        end
        datas[key] = []
        value.each_value do |v|
          datas[key] << v
        end
      end
      echart_data << datas
    end

    echart_data
  end
end

# ----------------------------------------------------------------------------------------------------
# format compare template results into a table format
#
class FormatTableData
  def initialize(result_hash, row_size = 8)
    @title = result_hash['title']
    @tables = result_hash['tables']
    @unit = result_hash['unit']
    @x_name = result_hash['x_name']
    @row_size = row_size
  end

  def show_table
    @tables.each do |table_title, table|
      @tb = Terminal::Table.new
      set_table_title
      row_num = get_row_num(table)
      split_data_column(table_title, table, row_num)
      set_align_column
      print_table
    end
  end

  def set_table_title
    @tb.title = "#{@title} (unit: #{@unit}, x_name: #{@x_name})"
  end

  def get_row_num(table)
    data_column_size = table['average']['source'][0].size
    unless @row_size.positive?
      warn('row size must be positive!')
      exit
    end
    (data_column_size / @row_size.to_f).ceil
  end

  def split_data_column(table_title, table, row_num)
    row_num.times do |row|
      starts = 1 + row * @row_size
      ends = starts + @row_size
      set_field_names(table_title, table, starts, ends)
      add_rows(table, starts, ends)
      break if row == row_num - 1

      @tb.add_separator
      @tb.add_separator
    end
  end

  def set_field_names(table_title, table, starts, ends)
    field_names = [table_title]
    field_names.concat(table['average']['source'][0][starts - 1...ends - 1])
    @tb.add_row(field_names)
    @tb.add_separator
  end

  def add_rows(table, starts, ends)
    row_names = %w[average standard_deviation change]
    max_size = row_names.map(&:size).max
    row_names.each do |row_name|
      next unless table[row_name]

      dimensions_size = table[row_name]['dimensions'].size
      (1...dimensions_size).each do |index|
        add_row(table, row_name, index, max_size, starts, ends)
      end
    end
  end

  def add_row(table, row_name, index, max_size, starts, ends)
    row = table[row_name]['source'][index]
    row_title = [row_name + ' ' * (max_size - row_name.size), row[0]].join(' ')
    format_data_row = row[starts...ends]
    if row_name == 'change'
      format_data_row.map! { |data| format('%.1f%%', data) }
    else
      format_data_row.map! { |data| format('%.2f', data) }
    end
    @tb.add_row([row_title, *format_data_row])
  end

  def set_align_column
    @tb.number_of_columns.times do |index|
      @tb.align_column(index + 1, :right)
    end
    @tb.align_column(0, :left)
  end

  def print_table
    puts @tb
    puts
  end
end

# input: x_params_list
# eg: ["1G|4K", "1G|1024k", "1G|128k", 2G|4k]
# output:
# ["1G|4K", "1G|128k", "1G|1024k", "2G|4k"]
def sort_x_params(x_params_list)
  x_params_hash = {}
  x_params_list.each do |param|
    params = param.gsub(/[a-zA-Z]+$/, '').split('|').map(&:to_i)
    x_params_hash[params] = param
  end

  x_params_hash.sort.map { |h| h[1] }
end

def numeric?(item)
  Float(item)
rescue
  nil
end

def score(item)
  score = 0
  return item.to_f*0.1 if numeric?(item)

  items = item.split('|')
  mutil = 1
  items.each do |i|
    v = i.sub(/[a-zA-Z]+/, '')
    if v.empty?
      return item
    else
      score += v.to_f * mutil
    end
    mutil *= 10
  end

  score
end

# sort Hash(compare_result) by key
# input like:
# {
#   "1G|4K" => {...},
#   "1G|1024k" => {...},
#   "1G|128k" => {...},
#   "2G|4k" => {...}
# }
# output:
# [
#  ["1G|4K", {...}],
#  ["1G|128k", {...}],
#  ["1G|1024k", {...}],
#  ["2G|4k", {...}]
# ]
def sort_compare_result(compare_result)
  compare_result.sort{|a, b| score(a[0]) <=> score(b[0])}
end
