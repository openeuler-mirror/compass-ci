# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'set'
require 'terminal-table'
require_relative 'es_query'
require_relative 'error_messages'
require_relative "#{ENV['LKP_SRC']}/lib/common"

def get_compare_result(previous_job_id, later_job_id)
  es = ESQuery.new

  previous_error_ids = es.query_by_id(previous_job_id)['error_ids']
  later_es_result = es.query_by_id(later_job_id)
  later_error_ids = later_es_result['error_ids']
  later_result_file = File.join('/srv', later_es_result['result_root'], 'build-pkg')

  new_error_ids =  get_new_error_ids(later_error_ids, previous_error_ids)
  error_messages = ErrorMessages.new(later_result_file).obtain_error_messages
  new_error_number, formatted_error_messages = format_error_messages(error_messages, new_error_ids)

  # new error use ">>" as an identifier in the error header
  return new_error_number, formatted_error_messages
end

def get_new_error_ids(later_error_ids, previous_error_ids)
  return nil_to_empty_array(later_error_ids) - nil_to_empty_array(previous_error_ids)
end

def nil_to_empty_array(array)
  array = [] if array.nil?
  return array
end

def format_error_messages(error_messages, new_error_ids)
  formatted_error_messages = Terminal::Table.new
  formatted_error_messages.style = { border_x: '', border_y: '', border_i: '', padding_left: 0 }
  new_error_number = 0

  error_messages.each do |k, v|
    if new_error_ids.include?("build-pkg.#{build_pkg_error_id(k)}")
      new_error_number += 1
      formatted_error_messages = add_sign(formatted_error_messages, '>>', v)
    else
      formatted_error_messages = add_sign(formatted_error_messages, '  ', v)
    end
  end

  return new_error_number, formatted_error_messages.to_s
end

def add_sign(formatted_error_messages, sign, set)
  set.each do |value|
    formatted_error_messages.add_row([sign, value])
  end

  return formatted_error_messages
end
