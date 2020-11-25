# SPDX-License-Identifier: MulanPSL-2.0+ or GPL-2.0
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)
require 'set'
require 'json/ext'
require_relative 'themes'
require_relative './compare_data_format.rb'
require "#{LKP_SRC}/lib/stats"

FAILURE_PATTERNS = IO.read("#{LKP_SRC}/etc/failure").split("\n")
LATENCY_PATTERNS = IO.read("#{LKP_SRC}/etc/latency").split("\n")

# Compute Tools

def get_matrix_size(matrix)
  if matrix.nil? || matrix.empty?
    0
  elsif matrix['stats_source']
    matrix['stats_source'].size
  else
    [matrix.values[0].size, matrix.values[-1].size].max
  end
end

def get_matrixes_size(matrixes_list)
  matrixes_size = {}
  matrixes_list.length.times do |index|
    matrixes_size[index] = get_matrix_size(matrixes_list[index])
  end
  matrixes_size
end

def fill_missing_with_zeros(value_list, matrix_size)
  value_list ||= [0] * matrix_size
  value_list << 0 while value_list.size < matrix_size
  value_list
end

def successful?(field)
  FAILURE_PATTERNS.all? { |pattern| field !~ /^#{pattern}/ }
end

def standard_deviation(value_list, average, length)
  Math.sqrt(
    value_list.reduce(0) do |result, v|
      result + (v - average)**2
    end / length.to_f
  )
end

def latency?(field)
  LATENCY_PATTERNS.any? { |pattern| field =~ /^#{pattern}/ }
end

# Core
def get_length_sum_average_sorted(value_list)
  length = value_list.length
  sum = value_list.sum
  average = sum / length.to_f
  sorted = value_list.sort
  return length, sum, average, sorted
end

def get_values(value_list, success)
  # get values(type: Hash) that include :average, :runs, :stddev_percent, ...
  #
  length, sum, average, sorted = get_length_sum_average_sorted(value_list)
  if success
    stddev_percent = nil
    if length > 1 && average != 0
      stddev_percent = (
        standard_deviation(value_list, average, length) * 100 / average
      ).to_i
    end
    { average: average, stddev_percent: stddev_percent,
      min: sorted[0], max: sorted[-1], sorted: sorted }
  else
    { average: average, fails: sum, runs: length,
      min: sorted[0], max: sorted[-1], sorted: sorted }
  end
end

def get_compare_value(base_value_average, value_average, success)
  # get compare value(change or reproduction)
  #
  if success
    return if base_value_average.zero?

    (100 * value_average / base_value_average - 100).round(1)
  else
    (100 * (value_average - base_value_average)).round(1)
  end
end

def field_changed?(base_values, values, success, field, options)
  # check matrix field if changed
  #
  changed_stats?(
    values[:sorted], values[:min],
    values[:average], values[:max],
    base_values[:sorted], base_values[:min],
    base_values[:average], base_values[:max],
    !success,
    latency?(field),
    field,
    options
  )
end

def set_compare_values(index, values, field, success, options)
  # set compare values, example average/ reproduction and check if changed
  #
  compare_str = success ? :change : :reproduction
  values[index][compare_str] = get_compare_value(
    values[0][:average],
    values[index][:average],
    success
  )
  values[:changed] |= field_changed?(
    values[0],
    values[index],
    success,
    field,
    options
  )
end

def get_values_by_field(matrixes_list, field, matrixes_size, success, options)
  # get values by field, values struct example: values[0][:average]
  #
  values = {}
  matrixes_list.length.times do |index|
    value_list = fill_missing_with_zeros(
      matrixes_list[index][field],
      matrixes_size[index]
    )
    values[index] = get_values(value_list, success)
    next if index.zero?

    set_compare_values(
      index, values,
      field, success,
      options
    )
  end

  values
end

def get_matrixes_fields(matrixes_list)
  # get all fields of matrixes
  #
  matrixes_fields = Set.new
  matrixes_list.each do |matrix|
    matrixes_fields |= Set.new(matrix.keys)
  end
  matrixes_fields
end

def get_matrixes_values(matrixes_list, options)
  # get all matrixes all field values
  #
  matrixes_values = { false => {}, true => {} }
  matrixes_size = get_matrixes_size(matrixes_list)
  get_matrixes_fields(matrixes_list).each do |field|
    next if field == 'stats_source'

    success = successful?(field)
    matrixes_values[success][field] = get_values_by_field(
      matrixes_list, field,
      matrixes_size, success, options
    )
  end
  matrixes_values
end

def remove_unchanged_field(matrixes_values)
  # remove unchanged field from matrixes valus and remove :changed key
  #
  matrixes_values.each_key do |success|
    matrixes_values[success].delete_if do |field|
      !matrixes_values[success][field].delete(:changed)
    end
  end
end

def matrixes_empty?(matrixes_list)
  return true if matrixes_list.nil?
  return true if matrixes_list.empty?

  return matrixes_list.any?(&:empty?)
end

def compare_matrixes(matrixes_list, suite_list, matrixes_titles = nil, group_key = nil, options: {})
  # compare matrix in matrixes_list and print info
  # @matrixes_list: list consisting of matrix
  # @matrixes_titles: number or dimension of matrix
  # @group_key: group_key of matrixes_list(only for group mode)
  # @options: compare options, type: hash
  return warn('Matrix cannot be empty!') || '' if matrixes_empty?(matrixes_list)

  options = { 'perf-profile': 5, theme: :none, no_print: false }.merge(options)
  matrixes_values = get_matrixes_values(matrixes_list, options)
  remove_unchanged_field(matrixes_values) if matrixes_list.length > 1
  no_print = options[:no_print]
  result_str = group_key ? "\n\n\n\n\n" + group_key : ''
  result_str += get_all_result_str(
    matrixes_values,
    suite_list,
    matrixes_titles,
    matrixes_list.size,
    options[:theme]
  )
  return result_str if no_print

  print result_str
end

# JSON Format

def print_json_result(matrixes_values, matrixes_titles)
  result = {
    'matrixes_titles': matrixes_titles,
    'success': matrixes_values[true],
    'failure': matrixes_values[false]
  }.to_json
  print result
end

# HTML Format

def get_html_index(matrixes_titles)
  index = "  <tr>\n    <th>0</th>\n"
  matrixes_titles.each do |matrix_index|
    index += "    <th colspan='2'>#{matrix_index}</th>\n"
  end
  index + "    <th>#{FIELD_STR}</th>\n  </tr>\n"
end

def get_html_title(common_title, compare_title, matrixes_titles)
  matrixes_number = matrixes_titles.size
  title = "  <tr>\n    <td>#{common_title}</td>\n"
  title += "    <td>#{compare_title}</td>\n    <td>#{common_title}</td>\n" * (
    matrixes_number - 1
  )
  title + "  </tr>\n"
end

def get_html_header(matrixes_titles, success)
  if success
    common_title = STDDEV_STR
    compare_title = CHANGE_STR
  else
    common_title = FAILS_RUNS_STR
    compare_title = REPRODUCTION_STR
  end

  header = get_html_index(matrixes_titles)
  header + get_html_title(common_title, compare_title, matrixes_titles)
end

def get_html_success(values, index)
  stddev_str = values[:average].to_s
  stddev_percent = values[:stddev_percent]
  if stddev_percent && stddev_percent != 0
    stddev_str += " ± #{stddev_percent}%"
  end

  change_str = "    <td>#{values[:change]}%</td>\n" unless index.zero?
  (change_str || '') + "    <td>#{stddev_str}</td>\n"
end

def get_html_failure(values, index)
  fails_runs_str = "#{values[:fails]}:#{values[:runs]}"
  reproduction_str = "    <td>#{values[:reproduction]}%</td>\n" unless index.zero?
  (reproduction_str || '') + "    <td>#{fails_runs_str}</td>\n"
end

def get_html_values(matrixes, success)
  html_values = ''
  matrixes.each do |index, values|
    html_values += if success
                     get_html_success(values, index)
                   else
                     get_html_failure(values, index)
                   end
  end
  html_values
end

def get_html_field(field)
  "    <td>#{field}</td>\n"
end

def print_html_result(matrixes_values, matrixes_titles, success)
  return if matrixes_values[success].empty?

  print "<table>\n"
  print get_html_header(matrixes_titles, success)
  matrixes_values[success].each do |field, matrixes|
    print "  <tr>\n"
    print get_html_values(matrixes, success)
    print get_html_field(field)
    print "  </tr>\n"
  end
  print '</table>'
end

# Format Tools
def get_decimal_length(number, length)
  return length - 7 if number.negative?

  return length - 6
end

def get_suitable_number_str(number, length, format_pattern)
  # if number string length can't < target length,
  # transform number string to scientific notation string

  format_str = format(format_pattern, number)
  return format_str if format_str.length <= length

  decimal_length = get_decimal_length(number, length)
  unless decimal_length.negative?
    scientific_str = format("%.#{decimal_length}e", number).sub('e+0', 'e+').sub('e-0', 'e-')
    lack_length = length - scientific_str.length
    unless lack_length.negative?
      return scientific_str + ' ' * lack_length
    end
  end
  format_str
end

# Colorize

def get_compare_value_color(value, theme)
  if value.nil?
  elsif value >= GOOD_STANDARD
    {
      foreground: theme[:good_foreground],
      background: theme[:good_background]
    }
  elsif value <= BAD_STANDARD
    {
      foreground: theme[:bad_foreground],
      background: theme[:bad_background]
    }
  end
end

def get_color_code(color_str)
  color_sym = color_str.to_sym if color_str.is_a?(String)
  COLORS[color_sym]
end

def replace_n(str, left_str, right_str)
  if str.index("\n")
    result_str = str.split("\n").join(right_str + "\n" + left_str)
    result_str = left_str + result_str + right_str
    result_str += "\n" if str[-1] == "\n"
    result_str
  else
    left_str + str + right_str
  end
end

def colorize(color, str)
  return str if color.nil? || color.empty?

  f_code = get_color_code(color[:foreground])
  b_code = get_color_code(color[:background])
  b_str = "\033[#{b_code + 10}m" if b_code
  f_str = "\033[#{f_code}m" if f_code
  left_str = "#{b_str}#{f_str}"
  return str if left_str == ''

  right_str = "\033[0m"
  replace_n(str, left_str, right_str)
end

# compare each matrices_list within pre dimension of group matrices
# input: group matrices
# output: pre compare result of each group
def compare_group_matrices(group_matrices, suites_list, options)
  result_str = ''
  group_matrices.each do |k, v|
    matrices_list = []
    matrices_titles = []
    v.each do |dim, matrix|
      matrices_titles << dim
      matrices_list << matrix
    end
    if options[:no_print]
      result_str += compare_matrixes(matrices_list, suites_list.shift, matrices_titles, k, options: options)
    else
      print compare_matrixes(matrices_list, suites_list.shift, matrices_titles, k, options: options)
    end
  end
  result_str
end

# input: groups_matrices
# {
#   group_key_1 => {
#     dimension_1 => matrix_1, (openeuler 20.03)
#     dimension_2 => matrix_2, (openeuler 20.09)
#     dimension_3 => matrix_3, (centos 7.6)
#   },
#   group_key_2 => {...}
# }
#
# output: compare_metrics_values
# {
#   group_key_1 => {
#     metric_1 => {
#       'average' => {
#         'dimension_1' => xxx
#         'dimension_2' => xxx
#         'dimension_3' => xxx
#       },
#       'standard_deviation' => {
#         'dimension_1' => xxx
#         'dimension_2' => xxx
#         'dimension_3' => xxx
#       },
#       'change' => {
#         'dimension_2 vs dimension_1' => xxx
#         'dimension_3 vs dimension_1' => xxx
#         'dimension_3 vs dimension_2' => xxx
#       }
#     },
#     metric_2 => {...}
#   }
# }
def compare_metrics_values(groups_matrices)
  metrics_compare_values = {}
  groups_matrices.each do |group_key, dimensions|
    metrics_compare_values[group_key] = get_metric_values(dimensions)
  end

  metrics_compare_values
end

def get_metric_values(dimensions)
  metrics_values = {}
  dimensions.each do |dim, matrix|
    matrix.each do |metric, values|
      assign_metric_values(metrics_values, dim, metric, values)
    end
  end
  assign_metric_change(metrics_values)

  metrics_values
end

def assign_metric_values(metrics_values, dim, metric, values)
  metrics_values[metric] ||= {}
  metrics_values[metric]['average'] ||= {}
  metrics_values[metric]['standard_deviation'] ||= {}
  metric_value = get_values(values, true)
  metrics_values[metric]['average'][dim] = metric_value[:average]
  metrics_values[metric]['standard_deviation'][dim] = metric_value[:stddev]
end

def assign_metric_change(metrics_values)
  metrics_values.each do |metric, values|
    next if values['average'].size < 2

    metrics_values[metric]['change'] = {}

    dimension_list = values['average'].keys
    dimension_groups = get_dimensions_combination(dimension_list)
    dimension_groups.each do |base_dimension, challenge_dimension|
      change = get_compare_value(values['average'][base_dimension], values['average'][challenge_dimension], true)
      values['change'] = { "#{challenge_dimension} vs #{base_dimension}" => change }
    end
  end
end

# input: dimension_list
#  eg: ['openeuler 20.03', 'debian sid', 'centos 7.6']
# output: Array(base_dimension: String, challenge_dimension: String)
#  [
#    ['openeuler 20.03', 'debian sid'],
#    ['openeuler 20.03', 'centos 7.6'],
#    ['debian sid', 'centos 7.6']
#  ]
def get_dimentions_combination(dimension_list)
  dims = []
  dimension_list_size = dimension_list.size
  (1..dimension_list_size - 1).each do |i|
    (i..dimension_list_size - 1).each do |j|
      dims << [dimension_list[i - 1], dimension_list[j]]
    end
  end

  dims
end

def show_compare_result(metrics_compare_results, template_params)
  formatter = FormatEchartData.new(metrics_compare_results, template_params)
  echart_results = formatter.format_for_echart
  print JSON.pretty_generate(echart_results)
end

# Format Fields

def format_fails_runs(fails, runs)
  fails_width = (SUB_LONG_COLUMN_WIDTH * FAILS_PROPORTION).to_i
  runs_width = SUB_LONG_COLUMN_WIDTH - fails_width - 1
  runs_str = get_suitable_number_str(
    runs,
    runs_width,
    "%-#{runs_width}d"
  )
  fails_str = get_suitable_number_str(
    fails,
    fails_width,
    "%#{fails_width}d"
  )
  fails_str + ':' + runs_str
end

def get_reproduction_index_str(reproduction, compare_index)
  reproduction_str = format('%+.1f%%', reproduction)
  reproduction_index = compare_index - reproduction_str.index('.')
  if reproduction_index.negative?
    reproduction_str = format('%+.1e%%', reproduction).sub('e+0', 'e+').sub('e-0', 'e-')
    reproduction_index = compare_index - reproduction_str.index('e') - 1
  end
  return reproduction_index, reproduction_str
end

def get_reprodcution(reproduction, compare_index)
  if reproduction
    reproduction_index, reproduction_str = get_reproduction_index_str(reproduction, compare_index)
    space_str = ' ' * (SUB_SHORT_COLUMN_WIDTH - reproduction_str.length)
    reproduction_str = space_str.insert(reproduction_index, reproduction_str)
  else
    reproduction_str = format("%-#{SUB_SHORT_COLUMN_WIDTH}s", '0')
  end
  reproduction_str
end

def format_reproduction(reproduction, theme, compare_index)
  color = get_compare_value_color(reproduction, theme)
  colorize(
    color,
    get_reprodcution(reproduction, compare_index)
  )
end

def get_change_index_str(change, compare_index)
  change_str = format('%+.1f%%', change)
  change_index = compare_index - change_str.index('.')
  if change_index.negative?
    change_str = format('%+.1e%%', change).sub('e+0', 'e+').sub('e-0', 'e-')
    change_index = compare_index - change_str.index('e') - 1
  end
  return change_index, change_str
end

def get_change(change, compare_index)
  if change
    change_index, change_str = get_change_index_str(change, compare_index)
    space_length = SUB_SHORT_COLUMN_WIDTH - change_str.length
    space_str = ' ' * space_length
    change_str = space_str.insert(change_index, change_str)
  else
    space_str = ' ' * (SUB_SHORT_COLUMN_WIDTH - 1)
    change_str = space_str.insert(compare_index, '0')
  end
  format("%-#{SUB_SHORT_COLUMN_WIDTH}s", change_str)
end

def format_change(change, theme, compare_index)
  color = get_compare_value_color(change, theme)
  colorize(
    color,
    get_change(change, compare_index)
  )
end

def format_stddev_percent(stddev_percent, average_width)
  percent_width = SUB_LONG_COLUMN_WIDTH - average_width
  if stddev_percent
    if stddev_percent != 0
      percent_str = get_suitable_number_str(
        stddev_percent.abs,
        percent_width - 4,
        "%-#{percent_width - 4}d"
      )
      space_index = percent_str.index(' ') || -1
      percent_str = percent_str.insert(space_index, '%')
      return " ± #{percent_str}"
    end
  end
  ' ' * percent_width
end

def format_stddev(average, stddev_percent)
  average_width = (
    SUB_LONG_COLUMN_WIDTH * STDDEV_AVERAGE_PROPORTION
  ).to_i
  average_str = get_suitable_number_str(
    average.round(2),
    average_width,
    "%#{average_width}.2f"
  )
  percent_str = format_stddev_percent(stddev_percent, average_width)
  average_str + percent_str
end

# Get Table Content

def get_index(matrixes_number)
  index_line = format("%#{SUB_LONG_COLUMN_WIDTH}d", 0)
  (1...matrixes_number).each do |index|
    index_line += INTERVAL_BLANK + format("%#{COLUMN_WIDTH}d", index)
  end
  index_line += INTERVAL_BLANK
  index_line += format("%-#{COLUMN_WIDTH}s\n", FIELD_STR)
  index_line
end

def get_dim(dims)
  index_line = format("%#{SUB_LONG_COLUMN_WIDTH}s", dims[0])
  (1...dims.size).each do |i|
    index_line += INTERVAL_BLANK + format("%#{COLUMN_WIDTH}s", dims[i])
  end
  index_line + INTERVAL_BLANK + format("%-#{COLUMN_WIDTH}s\n", FIELD_STR)
end

def get_liner(matrixes_number)
  liner = '-' * SUB_LONG_COLUMN_WIDTH
  liner + (INTERVAL_BLANK + '-' * COLUMN_WIDTH) * matrixes_number + "\n"
end

def get_base_matrix_title(common_title, common_index)
  str = ' ' * (SUB_LONG_COLUMN_WIDTH - common_title.length)
  str.insert(common_index, common_title)
end

def get_other_matrix_title(common_title, compare_title, common_index)
  column = ' ' * (
     COLUMN_WIDTH - common_title.length - compare_title.length
   )
  compare_index = (SUB_SHORT_COLUMN_WIDTH - compare_title.length) / 2
  compare_index = 0 if compare_index.negative?
  column = column.insert(compare_index, compare_title)
  column.insert(SUB_SHORT_COLUMN_WIDTH + common_index, common_title)
end

def get_other_matrixes_title(common_title, compare_title, matrixes_number, common_index)
  column = INTERVAL_BLANK + get_other_matrix_title(
    common_title, compare_title, common_index
  )
  column * (matrixes_number - 1)
end

def get_title_name(success)
  if success
    common_title = STDDEV_STR
    compare_title = CHANGE_STR
  else
    common_title = FAILS_RUNS_STR
    compare_title = REPRODUCTION_STR
  end
  return common_title, compare_title
end

def get_title(common_title, compare_title, matrixes_number, success, common_index)
  common_index -= if success
                    common_title.length / 2
                  else
                    common_title.index(':')
                  end
  title = get_base_matrix_title(common_title, common_index)
  title += get_other_matrixes_title(
    common_title, compare_title, matrixes_number, common_index
  )
  title += INTERVAL_BLANK + ' ' * COLUMN_WIDTH
  title + "\n"
end

def get_base_matrix_title_symbol(common_index, success)
  title_symbol = ' ' * SUB_LONG_COLUMN_WIDTH
  title_symbol[common_index] = success ? '\\' : '|'
  title_symbol
end

def get_other_matrixes_title_symbol(_compare_title, matrixes_number, common_index, success)
  title_symbol = ' ' * (
    (INTERVAL_WIDTH + COLUMN_WIDTH) * matrixes_number
  )
  start_point = 0

  common_symbol = success ? '\\' : '|'
  compare_symbol = '|'
  compare_index = SUB_SHORT_COLUMN_WIDTH / 2

  (matrixes_number - 1).times do |_|
    start_point += INTERVAL_WIDTH
    title_symbol[start_point + compare_index] = compare_symbol
    title_symbol[start_point + SUB_SHORT_COLUMN_WIDTH + common_index] = common_symbol
    start_point += COLUMN_WIDTH
  end
  title_symbol
end

def get_title_symbol(compare_title, matrixes_number, common_index, success)
  title_symbol = get_base_matrix_title_symbol(common_index, success)
  title_symbol += get_other_matrixes_title_symbol(
    compare_title, matrixes_number, common_index, success
  )
  title_symbol + "\n"
end

def get_header(matrixes_titles, success, common_title, compare_title)
  common_index = if success
                   #  average + " + " + standard_deviation
                   STDDEV_AVERAGE_PROPORTION * SUB_LONG_COLUMN_WIDTH + 1
                 else
                   #  fails + ":" + runs
                   FAILS_PROPORTION * SUB_LONG_COLUMN_WIDTH
                 end

  header, matrixes_number = get_first_header(matrixes_titles)
  header += get_liner(matrixes_number)
  header += get_title(common_title, compare_title, matrixes_number, success, common_index)
  header += get_title_symbol(
    compare_title,
    matrixes_number,
    common_index,
    success
  )
  header
end

def get_first_header(matrixes_titles)
  if matrixes_titles.is_a?(Array)
    matrixes_number = matrixes_titles.size
    header = get_dim(matrixes_titles)
  else
    matrixes_number = matrixes_titles
    header = get_index(matrixes_number)
  end
  [header, matrixes_number]
end

def get_success_str(values, index, theme, compare_index)
  change_str = format_change(values[:change], theme, compare_index) unless index.zero?
  stddev_str = format_stddev(
    values[:average],
    values[:stddev_percent]
  )
  (change_str || '') + stddev_str
end

def get_failure_str(values, index, theme, compare_index)
  unless index.zero?
    reproduction_str = format_reproduction(
      values[:reproduction], theme, compare_index
    )
  end

  fails_runs_str = format_fails_runs(
    values[:fails],
    values[:runs]
  )
  (reproduction_str || '') + fails_runs_str
end

def get_values_str(matrixes, success, theme)
  values_str = ''
  compare_index = SUB_SHORT_COLUMN_WIDTH / 2
  matrixes.each do |index, values|
    values_str += if success
                    get_success_str(
                      values, index, theme, compare_index
                    ) + INTERVAL_BLANK
                  else
                    get_failure_str(
                      values, index, theme, compare_index
                    ) + INTERVAL_BLANK
                  end
  end
  values_str
end

def get_field_str(field)
  format("%-#{COLUMN_WIDTH}s", field)
end

# Print
def get_theme(matrixes_values, matrixes_titles, theme)
  theme = theme.to_sym if theme.is_a?(String)
  if theme == :html
    print_html_result(matrixes_values, matrixes_titles, false)
    print_html_result(matrixes_values, matrixes_titles, true)
    return
  elsif theme == :json
    return print_json_result(matrixes_values, matrixes_titles)
  end
  return THEMES[theme] if THEMES.key?(theme)

  warn "Theme #{theme} does not exist! use default theme."
  return THEMES[:none]
end

def get_all_result_str(matrixes_values, suite_list, matrixes_titles, matrixes_number, theme)
  matrixes_titles ||= matrixes_number.times.to_a.map(&:to_s)
  theme = get_theme(matrixes_values, matrixes_titles, theme)
  return '' unless theme

  failure_str = get_result_str(matrixes_values[false].sort, suite_list, matrixes_titles, false, theme)
  success_str = get_result_str(matrixes_values[true].sort, suite_list, matrixes_titles, true, theme)
  failure_str + success_str
end

def get_result_str(values, suite_list, matrixes_titles, success, theme)
  return '' if values.empty?

  suite_set = Set.new(suite_list)
  result_str = "\n\n\n"
  common_title, compare_title = get_title_name(success)
  result_str += get_header(matrixes_titles, success, common_title, compare_title)
  ranked_str = get_ranked_str(values, suite_set, success, theme)
  result_str += ranked_str
  result_str
end

def get_ranked_str(values, suite_set, success, theme)
  suite_str = ''
  common_str = ''
  values.each do |field, matrixes|
    row = get_values_str(matrixes, success, theme)
    row += get_field_str(field) + "\n"
    field_start_with_suite = suite_set.any? { |suite| field.start_with?(suite) }
    if field_start_with_suite
      suite_str += row
    else
      common_str += row
    end
  end
  suite_str + common_str
end
