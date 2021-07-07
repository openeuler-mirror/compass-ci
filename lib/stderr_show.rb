# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require_relative '../src/lib/web_backend.rb'
require 'terminal-table'
require 'json'

class StderrTable
  def initialize(top_num = 1000)
    @head = []
    @rows = []
    @top_num = top_num
  end

  def init
    begin
      response = JSON.parse(active_stderr_body)
    rescue StandardError => e
      e.message
    end

    @head = response['cols'][0, 2] + ['error_message/relevant_links']
    response['data'][0, @top_num].each do |item|
      relevant_links = '/srv' + handle_long_str(item['relevant_links'], 134)
      error_message = handle_long_str(item['error_message'], 138)
      @rows << [item['count'], item['first_date'], error_message + "\n  - " + relevant_links]
    end
  end

  def create_table
    init

    Terminal::Table::Style.defaults = { border: :unicode_round }
    table = Terminal::Table.new do |t|
      t.title = 'Compass-ci Daily Stderr'
      t.headings = @head
      t.rows = @rows
      t.style = { all_separators: true }
    end

    table
  end
end

def handle_long_str(str, warp_size)
  return str if str.size <= warp_size

  str.slice!(0, warp_size) + "\n" + handle_long_str(str, warp_size)
end
