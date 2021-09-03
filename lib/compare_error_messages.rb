# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'set'
require 'terminal-table'
require_relative 'es_query'
require_relative 'error_messages'
require_relative "#{ENV['LKP_SRC']}/lib/common"

module CEM
  extend self

  # previous_job_id's error_ids include error_id
  # If lttr_job_id's output include error filename that extract from error_id,
  # the lttr_job_id is credible.
  def credible?(prev_job_id, lttr_job_id, error_id)
    es = ESQuery.new
    lttr_es_result = es.query_by_id(lttr_job_id)

    return true if lttr_es_result['job_state'] == 'finished'

    prev_es_result = es.query_by_id(prev_job_id)
    prev_result_file = File.join('/srv', prev_es_result['result_root'], 'build-pkg')
    lttr_result_file = File.join('/srv', lttr_es_result['result_root'], 'build-pkg')

    check_result = filenames_check(prev_result_file, lttr_result_file, error_id)

    return false if check_result.empty? || check_result.value?(false)

    return true
  end

  def filenames_check(prev_result_file, lttr_result_file, error_id)
    filenames = Set.new
    ret = Hash.new { |h, k| h[k] = false }

    error_lines = ErrorMessages.new(prev_result_file).obtain_error_messages_by_error_id(error_id, true)
    error_lines.each do |error_line|
      # "/usr/lib/postgresql/pgxs/src/makefiles/pgxs.mk:433: warning: ignoring old recipe for target 'check'"
      # => "/usr/lib/postgresql/pgxs/src/makefiles/pgxs"
      # "src/ssl_sock.c:1454:104: warning: unused parameter 'al' [-Wunused-parameter]" => "src/ssl_sock"
      # "/tmp/lkp/bart-git/src/bart/src/num/lapack.c:20:10: fatal error: lapacke.h: No such file or directory"
      # => "/tmp/lkp/bart-git/src/bart/src/num/lapack"
      filenames << $1.chomp(File.extname($1)) if error_line =~ /(.*)(:\d+){1,2}: ((fatal )?error|warning):/
    end

    File.open(lttr_result_file).each_line do |line|
      filenames.each do |filename|
        # default init filename value to false
        ret[filename]
        ret[filename] = true if line.include?(filename)
      end
    end

    return ret
  end

  def get_compare_result(previous_job_id, later_job_id)
    es = ESQuery.new

    previous_error_ids = es.query_by_id(previous_job_id)['error_ids']
    later_es_result = es.query_by_id(later_job_id)
    later_error_ids = later_es_result['error_ids']
    later_result_file = File.join('/srv', later_es_result['result_root'], "build-pkg")

    new_error_ids =  get_new_error_ids(later_error_ids, previous_error_ids)
    error_messages = ErrorMessages.new(later_result_file).obtain_error_messages
    new_error_number, formatted_error_messages = format_error_messages(error_messages, new_error_ids)

    # new error use ">>" as an identifier in the error header
    return new_error_number, formatted_error_messages
  end

  def get_error_messages(job_id, error_id)
    es_result = ESQuery.new.query_by_id(job_id)
    result_file = File.join('/srv', es_result['result_root'], "build-pkg")
    return ErrorMessages.new(result_file).obtain_error_messages_by_error_id(error_id)
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
      elsif new_error_ids.include?("pkgbuild.#{build_pkg_error_id(k)}")
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
end
