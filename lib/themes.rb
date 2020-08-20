# frozen_string_literal: true

COLUMN_WIDTH = 30 # print column width
INTERVAL_WIDTH = 1 # width of interval that between column
INTERVAL_BLANK = ' ' * INTERVAL_WIDTH

# the sub_column that are children of column
# sub_short_column_width : sub_long_column_width = 1 : 3
# the short sub_column
SUB_SHORT_COLUMN_WIDTH = (COLUMN_WIDTH / 3.0).to_i

# the long sub_column
SUB_LONG_COLUMN_WIDTH = COLUMN_WIDTH - SUB_SHORT_COLUMN_WIDTH

CHANGE_STR = 'change'
STDDEV_STR = '%stddev'
STDDEV_AVERAGE_PROPORTION = 5 / 8.0
FIELD_STR = 'metric'
RUNS_FAILS_STR = 'runs:fails'
REPRODUCTION_STR = 'reproduction'
RUNS_PROPORTION = 3 / 7.0

# when change or reproduction greater or equal to GOOD_STANDARD
# change show color.
# example: 100 mean 100%
GOOD_STANDARD = 15

# same as GOOD_STANDARD
BAD_STANDARD = -15

COLORS = {
  default: 39,
  black: 30,
  red: 31,
  green: 32,
  yellow: 33,
  blue: 34,
  magenta: 35,
  cyan: 36,
  'light gray': 37,
  'dark gray': 90,
  'light red': 91,
  'light yellow': 93,
  'light blue': 94,
  'light magenta': 95,
  'light cyan': 96,
  white: 97
}.freeze

THEMES = {
  none: {},
  classic: {
    good_foreground: 'light yellow',
    bad_foreground: 'light red'
  },
  focus_good: {
    good_foreground: 'light yellow'
  },
  focus_bad: {
    bad_foreground: 'light red'
  },
  striking: {
    good_foreground: 'black',
    good_background: 'light yellow',
    bad_foreground: 'black',
    bad_background: 'light red'
  },
  light: {
    good_foreground: 'light blue',
    good_background: 'white',
    bad_foreground: 'light red',
    bad_background: 'white'
  }
}.freeze
