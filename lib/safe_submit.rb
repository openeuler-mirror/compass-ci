#!/usr/bin/ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'open3'
require 'json'
require_relative 'json_logger.rb'


def syscall(*cmd)
  begin
    stdout, stderr, status = Open3.capture3(*cmd)
    status.success? && stdout.slice!(0..-(1 + $/.size))
  rescue StandardError => e
    @log.warn({
      "syscall error message": e.backtrace
    }.to_json)
  end
end

def safe_submit(*cmd)
  stdout = syscall(*cmd)
  unless stdout
    @log.warn({
      "submit job error message": "submit job failed, please check scheduler"
    }.to_json)

    sleep 1800
    safe_submit(*cmd)
  else
    if stdout.include?("got job id=#{ENV['lab']}.")
      @log.info({"submit job message": "submit job success"}.to_json)
    else
      @log.warn({"submit job error message": "submit job failed"}.to_json)

      sleep 60
      safe_submit(*cmd)
    end
  end
end

