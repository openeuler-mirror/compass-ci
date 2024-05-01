#!/usr/bin/env crystal

def to_seconds(time_spec)
  return time_spec if time_spec.is_a?(Number)

  n = time_spec.to_i

  case time_spec[-1]
  when "y"
    return n * 3600 * 24 * 365
  when "w"
    return n * 3600 * 24 * 7
  when "d"
    return n * 3600 * 24
  when "h"
    return n * 3600
  when "m"
    return n * 60
  when "s"
    return n
  else
    return n
  end
end

SIZE_UNITS = {
  P: 50,
  T: 40,
  G: 30,
  M: 20,
  K: 10,
}.freeze

def to_byte(size_spec)
  return size_spec unless size_spec.is_a?(String)

  unit = size_spec.sub(/^\d+/, "").upcase.chomp("B")
  shift = SIZE_UNITS[unit.to_sym]
  if shift
    n = size_spec.to_i
    n << shift
  else
    size_spec
  end
end
