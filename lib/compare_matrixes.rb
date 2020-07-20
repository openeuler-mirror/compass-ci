# frozen_string_literal: true

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require 'set'

COLUMN_WIDTH = 38 # print column width
INTERVAL_WIDTH = 3 # width of interval that between column
INTERVAL_BLANK = ' ' * INTERVAL_WIDTH

# the sub_column that are children of column
# the short sub_column, sub_short_column_width : sub_long_column_width = 1 : 3
SUB_SHORT_COLUMN_WIDTH = (COLUMN_WIDTH / 4.0).to_i
SUB_LONG_COLUMN_WIDTH = COLUMN_WIDTH - SUB_SHORT_COLUMN_WIDTH # the long sub_column

CHANGE_STR = 'change'
STDDEV_STR = '%stddev'
STDDEV_AVERAGE_PROPORTION = 5 / 8.0
FIELD_STR = 'field'
RUNS_FAILS_STR = 'runs:fails'
REPRODUCTION_STR = 'reproduction'

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)
FAILURE_PATTERNS = IO.read("#{LKP_SRC}/etc/failure").split("\n")

# Tools

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
  FAILURE_PATTERNS.each do |pattern|
    return false if field =~ /^#{pattern}/
  end
  true
end

# Core

def get_values(value_list, success)
  # get values(type: Hash) that include 'average', 'runs', 'stddev_percent', ...
  #
  sum = value_list.sum
  length = value_list.length
  average = sum / length
  if success
    stddev_percent = nil
    stddev_percent = (value_list.standard_deviation * 100 / average).to_i if length > 1 && average != 0
    { 'average' => average, 'stddev_percent' => stddev_percent }
  else
    { 'average' => average, 'runs' => sum, 'fails' => length }
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

def get_values_by_field(matrixes_list, field, matrixes_size, success)
  # get values by field, values struce example: values[0]['average']
  #
  values = {}
  (0...matrixes_list.length).each do |index|
    values[index] = get_values(fill_missing_with_zeros(matrixes_list[index][field], matrixes_size[index]), success)
    next if index.zero?

    compare_str = success ? 'change' : 'reproduction'
    values[index][compare_str] = get_compare_value(values[0]['average'], values[index]['average'], success)
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

def get_matrixes_values(matrixes_list)
  # get all matrixes all field values
  #
  matrixes_values = { false => {}, true => {} }
  matrixes_size = get_matrixes_size(matrixes_list)
  get_matrixes_fields(matrixes_list).each do |field|
    success = success?(field)
    matrixes_values[success][field] = get_values_by_field(matrixes_list, field, matrixes_size, success)
  end
  matrixes_values
end

def compare_matrixes(matrixes_list)
  # compare matrix in matrixes_list and print info
  #
  # @matrixes_list: list consisting of matrix
  #
  matrixes_value = get_matrixes_values(matrixes_list)
  print_result(matrixes_value, matrixes_list.length, false)
  print_result(matrixes_value, matrixes_list.length, true)
end
