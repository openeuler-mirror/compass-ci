# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'logger'

# records the run logs of the ruby program
class Log < Logger
  def initialize(filename)
    super(filename)
    format
  end

  private

  def format
    self.datetime_format = '%Y-%m-%d %H:%M:%s'
    self.formatter = proc do |severity, datetime, _progname, msg|
      transform_msg(msg).map { |m| "#{datetime} #{severity} -- #{m}\n" }.join
    end
  end

  def transform_msg(msg)
    msg = if msg.is_a? Exception
            ["#{msg.backtrace.first}: #{msg.message.split("\n").first} (#{msg.class.name})",
             msg.backtrace[1..-1].map { |m| "\tfrom #{m}" }].flatten
          else
            msg.to_s.split("\n")
          end
    return msg
  end
end
