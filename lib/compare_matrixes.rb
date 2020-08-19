# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)
require 'set'
require 'json/ext'
require_relative 'themes'
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

def success?(field)
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

def get_values(value_list, success)
  # get values(type: Hash) that include :average, :runs, :stddev_percent, ...
  #
  sum = value_list.sum
  length = value_list.length
  average = sum / length
  sorted = value_list.sort
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
  # get values by field, values struce example: values[0][:average]
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

    success = success?(field)
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

def compare_matrixes(matrixes_list, options = {})
  # compare matrix in matrixes_list and print info
  #
  # @matrixes_list: list consisting of matrix
  # @options: compare options, type: hash

  if matrixes_empty?(matrixes_list)
    warn 'Matrix cannot be empty!'
    return
  end

  options = { 'perf-profile': 5, theme: :none }.merge(options)
  matrixes_values = get_matrixes_values(matrixes_list, options)
  remove_unchanged_field(matrixes_values)
  show_result(
    matrixes_values,
    matrixes_list.length,
    options[:theme]
  )
end

# JSON Format

def print_json_result(matrixes_values, matrixes_number)
  result = {
    'matrixes_indexes': Array.new(matrixes_number) { |i| i },
    'success': matrixes_values[true],
    'failure': matrixes_values[false]
  }.to_json
  print result
end

# HTML Format

def get_html_index(matrixes_number)
  index = "  <tr>\n    <th>0</th>\n"
  (1...matrixes_number).each do |matrix_index|
    index += "    <th colspan='2'>#{matrix_index}</th>\n"
  end
  index + "    <th>#{FIELD_STR}</th>\n  </tr>\n"
end

def get_html_title(common_title, compare_title, matrixes_number)
  title = "  <tr>\n    <td>#{common_title}</td>\n"
  title += "    <td>#{compare_title}</td>\n    <td>#{common_title}</td>\n" * (
    matrixes_number - 1
  )
  title + "  </tr>\n"
end

def get_html_header(matrixes_number, success)
  if success
    common_title = STDDEV_STR
    compare_title = CHANGE_STR
  else
    common_title = RUNS_FAILS_STR
    compare_title = REPRODUCTION_STR
  end

  header = get_html_index(matrixes_number)
  header + get_html_title(common_title, compare_title, matrixes_number)
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
  runs_fails_str = "#{values[:runs]}:#{values[:fails]}"
  reproduction_str = "    <td>#{values[:reproduction]}%</td>\n" unless index.zero?
  (reproduction_str || '') + "    <td>#{runs_fails_str}</td>\n"
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

def print_html_result(matrixes_values, matrixes_number, success)
  return if matrixes_values[success].empty?

  print "<table>\n"
  print get_html_header(matrixes_number, success)
  matrixes_values[success].each do |field, matrixes|
    print "  <tr>\n"
    print get_html_values(matrixes, success)
    print get_html_field(field)
    print "  </tr>\n"
  end
  print '</table>'
end

# Format Tools

def get_suitable_number_str(number, length, format_pattern)
  # if number string length can't < target length,
  # transform number string to scientific notation string

  format_str = format(format_pattern, number)
  return format_str if format_str.length <= length

  number_length = length - 7
  unless number_length.negative?
    scientific_str = format("%+.#{number_length}e", number)
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
  COLORS.key?(color_sym) ? COLORS[color_sym] : COLORS[:default]
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

  foreground_color = get_color_code(color[:foreground])
  background_color = get_color_code(color[:background]) + 10
  left_str = "\033[#{background_color}m\033[#{foreground_color}m"
  right_str = "\033[0m"
  replace_n(str, left_str, right_str)
end

# Format Fields

def format_runs_fails(runs, fails)
  runs_width = (SUB_LONG_COLUMN_WIDTH * RUNS_PROPORTION).to_i
  fails_width = SUB_LONG_COLUMN_WIDTH - runs_width - 3
  runs_str = get_suitable_number_str(
    runs,
    runs_width,
    "%#{runs_width}d"
  )
  fails_str = get_suitable_number_str(
    fails,
    fails_width,
    "%-#{fails_width}d"
  )
  runs_str + ' : ' + fails_str
end

def format_reproduction(reproduction, theme)
  reproduction_str = get_suitable_number_str(
    reproduction,
    SUB_SHORT_COLUMN_WIDTH - 1,
    '%+.1f'
  ) + '%'
  color = get_compare_value_color(reproduction, theme)
  colorize(
    color,
    format("%-#{SUB_SHORT_COLUMN_WIDTH}s", reproduction_str)
  )
end

def format_change(change, theme)
  change_str = '0'
  if change
    change_str = get_suitable_number_str(
      change,
      SUB_SHORT_COLUMN_WIDTH - 3,
      '%+.1f'
    ) + '%'
  end
  color = get_compare_value_color(change, theme)
  colorize(
    color,
    format("%-#{SUB_SHORT_COLUMN_WIDTH}s", change_str)
  )
end

def format_stddev_percent(stddev_percent, average_width)
  percent_width = SUB_LONG_COLUMN_WIDTH - average_width
  if stddev_percent
    if stddev_percent != 0
      percent_width -= 4
      percent_str = get_suitable_number_str(
        stddev_percent.abs,
        percent_width,
        "%#{percent_width}d"
      )
      # that symbol print width is 2
      return " ±#{percent_str}%"
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

def get_liner(matrixes_number)
  liner = '-' * SUB_LONG_COLUMN_WIDTH
  liner + (INTERVAL_BLANK + '-' * COLUMN_WIDTH) * matrixes_number + "\n"
end

def get_base_matrix_title(common_title)
  format("%#{SUB_LONG_COLUMN_WIDTH}s", common_title)
end

def get_other_matrixes_title(common_title, compare_title, matrixes_number)
  column = compare_title + ' ' * (
    COLUMN_WIDTH - common_title.length - compare_title.length
  )
  column += common_title
  column * (matrixes_number - 1)
end

def get_title(common_title, compare_title, matrixes_number)
  title = get_base_matrix_title(common_title)
  title += INTERVAL_BLANK + get_other_matrixes_title(
    common_title, compare_title, matrixes_number
  )
  title += INTERVAL_BLANK + ' ' * COLUMN_WIDTH
  title + "\n"
end

def get_base_matrix_title_symbol(common_title)
  title_symbol = ' ' * SUB_LONG_COLUMN_WIDTH
  title_symbol[
    INTERVAL_WIDTH + SUB_LONG_COLUMN_WIDTH - common_title.length / 2
  ] = '\\'
  title_symbol
end

def get_other_matrixes_title_symbol(common_title, compare_title, matrixes_number)
  title_symbol = ' ' * (
    (INTERVAL_WIDTH + COLUMN_WIDTH) * matrixes_number
  )
  start_point = 0
  half_compare_title_length = compare_title.length / 2
  half_common_title_length = common_title.length / 2

  (matrixes_number - 1).times do |_|
    start_point += INTERVAL_WIDTH
    title_symbol[start_point + half_compare_title_length] = '|'
    start_point += COLUMN_WIDTH
    title_symbol[start_point - half_common_title_length] = '\\'
  end
  title_symbol
end

def get_title_symbol(common_title, compare_title, matrixes_number)
  title_symbol = get_base_matrix_title_symbol(common_title)
  title_symbol += get_other_matrixes_title_symbol(
    common_title, compare_title, matrixes_number
  )
  title_symbol + "\n"
end

def get_header(matrixes_number, success)
  if success
    common_title = STDDEV_STR
    compare_title = CHANGE_STR
  else
    common_title = RUNS_FAILS_STR
    compare_title = REPRODUCTION_STR
  end

  header = get_index(matrixes_number)
  header += get_liner(matrixes_number)
  header += get_title(common_title, compare_title, matrixes_number)
  header += get_title_symbol(
    common_title,
    compare_title,
    matrixes_number
  )
  header
end

def get_success_str(values, index, theme)
  change_str = format_change(values[:change], theme) unless index.zero?
  stddev_str = format_stddev(
    values[:average],
    values[:stddev_percent]
  )
  (change_str || '') + stddev_str
end

def get_failure_str(values, index, theme)
  unless index.zero?
    reproduction_str = format_reproduction(
      values[:reproduction], theme
    )
  end

  runs_fails_str = format_runs_fails(
    values[:runs],
    values[:fails]
  )
  (reproduction_str || '') + runs_fails_str
end

def get_values_str(matrixes, success, theme)
  values_str = ''
  matrixes.each do |index, values|
    values_str += if success
                    get_success_str(
                      values, index, theme
                    ) + INTERVAL_BLANK
                  else
                    get_failure_str(
                      values, index, theme
                    ) + INTERVAL_BLANK
                  end
  end
  values_str
end

def get_field_str(field)
  format("%-#{COLUMN_WIDTH}s", field)
end

# Print

def show_result(matrixes_values, matrixes_list_length, theme)
  if theme.is_a?(String)
    theme = theme.to_sym
  end
  if theme == :html
    print_html_result(matrixes_values, matrixes_list_length, false)
    print_html_result(matrixes_values, matrixes_list_length, true)
    return
  elsif theme == :json
    print_json_result(matrixes_values, matrixes_list_length)
    return
  end

  if THEMES.key?(theme)
    theme = THEMES[theme]
  else
    warn "Theme #{theme} does not exist! use default theme."
    theme = THEMES[:none]
  end

  print_result(matrixes_values, matrixes_list_length, false, theme)
  print_result(matrixes_values, matrixes_list_length, true, theme)
end

def print_result(matrixes_values, matrixes_number, success, theme)
  return if matrixes_values[success].empty?

  print "\n\n\n"
  print get_header(matrixes_number, success)
  matrixes_values[success].each do |field, matrixes|
    print get_values_str(matrixes, success, theme)
    print get_field_str(field)
    print "\n"
  end
end
