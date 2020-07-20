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
